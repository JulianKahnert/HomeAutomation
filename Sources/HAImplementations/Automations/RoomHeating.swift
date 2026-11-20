//
//  RoomHeating.swift
//  HAImplementations
//

import Foundation
import HAModels

/// Heats one room (glossary: room) after its plan. It is the only writer of the room's radiators.
///
/// It writes the plan target at each switch point and once after a configuration deploy. A plain server
/// start re-applies only the overrides (an open window, the fireplace on) and writes no plan target, so a
/// manual change at a radiator stays until the next switch point.
public struct RoomHeating: Automatable {
    public var isActive = true
    public let name: String
    public let placeId: PlaceId
    public let radiators: [Radiator]
    /// Contacts that switch the room off while open (glossary: contact): the window contacts of the room and
    /// the fireplace switch when the room follows it (all radiators, or only those the contact lists).
    public let contacts: [RoomContact]
    /// `nil` for a room without a plan of its own: it follows the standard plan.
    public let plan: HeatingPlan?
    public let configuration: HeatingConfiguration
    /// The room's own temperature sensor; `nil` when the actual value is the mean of the radiators.
    public let roomSensor: EntityId?
    /// The name of the room in the Heizung tab; `nil` shows the `placeId`.
    public let displayName: String?
    /// The label under the room's bar in the overview; `nil` derives it from the name.
    public let shortLabel: String?

    public var triggerEntityIds: Set<EntityId> { Set(contacts.map(\.entityId)) }

    /// The plan this room follows.
    public var effectivePlan: HeatingPlan { plan ?? configuration.standardPlan }

    public init(_ name: String, placeId: PlaceId, radiators: [Radiator], contacts: [RoomContact] = [], plan: HeatingPlan? = nil, roomSensor: EntityId? = nil, displayName: String? = nil, shortLabel: String? = nil, configuration: HeatingConfiguration) {
        self.displayName = displayName
        self.shortLabel = shortLabel
        self.roomSensor = roomSensor
        self.name = name
        self.placeId = placeId
        self.radiators = radiators
        self.contacts = contacts
        self.plan = plan
        self.configuration = configuration
    }

    /// What the room endpoint needs to build the detail of this room.
    public var heatingSources: HeatingRoomSources {
        var sources = HeatingRoomSources(placeId: placeId,
                           name: displayName ?? placeId,
                           radiators: radiators.map { .init(name: $0.heatingId.name, temperatureId: $0.temperatureId, valvePositionId: $0.valvePositionId, targetTemperatureId: $0.targetTemperatureId) },
                           roomSensor: roomSensor,
                           plan: effectivePlan,
                           followsFireplace: contacts.contains { if case .fireplace = $0 { true } else { false } },
                           contacts: contacts.map { contact in
                               switch contact {
                               case .window(let sensor): .init(source: .window, name: sensor.contactSensorId.name, entityId: sensor.contactSensorId)
                               case .fireplace(let device, _): .init(source: .fireplace, name: "Kamin", entityId: device.switchId)
                               }
                           })
        sources.shortName = shortLabel
        return sources
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        switch event {
        case .time(let date):
            return effectivePlan.switchPoint(at: date) != nil
        case .configDeployed:
            return true
        case .change(let item):
            guard let contact = contacts.first(where: { $0.entityId == item.entityId }) else { return false }
            // An opening starts the delay. A closing matters only when it ends a state the server acted on:
            // the re-sent closed contacts after a restart or a cache expiry must not write the plan over a
            // manual change.
            if contact.isOpen(item) { return true }
            return await endedOffState(of: contact, using: hm)
        case .serverStarted:
            // Re-apply the overrides from the stored contact states, without waiting for the adapter to
            // re-send them. All closed: nothing to do, the radiators keep their manual values.
            return await !offStates(using: hm).isEmpty
        case .sunrise, .sunset:
            return false
        }
    }

    public func execute(using hm: HomeManagable) async throws {
        try await execute(using: hm, now: Date(), sleep: { try await Task.sleep(for: $0) })
    }

    /// Recomputes the room from `now` and the contacts, so a trigger that supersedes a running run (even
    /// one sleeping in the window delay) needs nothing from it. Every radiator follows the contacts that
    /// affect it (glossary: contact); the others follow the plan.
    ///
    /// - A radiator with a contact open for the delay: off, reason of that contact. A contact open for less
    ///   waits the rest of the delay and looks again; a run cancelled meanwhile writes nothing.
    /// - A radiator without: the plan target at a switch point (reason `plan`), when the contact that took
    ///   it off just closed (reason of the contact: back to the plan at once, not to an old manual value),
    ///   and `system` after a deploy. A switch point while a radiator is off records the plan target for the
    ///   history without sending it. A radiator that no switch point and no closing concerns keeps its value.
    func execute(using hm: HomeManagable, now: Date, sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async throws {
        let plan = effectivePlan
        let isSwitchPoint = plan.switchPoint(at: now) != nil
        let initialOffs = await offStates(using: hm)

        if !initialOffs.isEmpty {
            if isSwitchPoint {
                await recordPlanTargetWhileOff(of: initialOffs.map(\.radiator), at: now, using: hm)
            }
            var current = now
            var written: Set<EntityId> = []
            while true {
                // the contacts may have changed while waiting: look again
                let offs = await offStates(using: hm).filter { !written.contains($0.radiator.heatingId) }
                guard !offs.isEmpty else { return }
                for off in offs where off.at <= current {
                    written.insert(off.radiator.heatingId)
                    await HeatingWriteContext.withReason(off.contact.reason) {
                        await off.radiator.turnOff(with: hm)
                    }
                }
                guard let next = offs.map(\.at).filter({ $0 > current }).min() else { break }
                try await sleep(.seconds(next.timeIntervalSince(current)))
                current = next
            }
            let others = radiators.filter { radiator in !initialOffs.contains { $0.radiator.heatingId == radiator.heatingId } }
            try await writePlan(to: others, now: now, isSwitchPoint: isSwitchPoint, isDeploy: false, using: hm)
            return
        }
        try await writePlan(to: radiators, now: now, isSwitchPoint: isSwitchPoint, isDeploy: true, using: hm)
    }

    /// Writes the plan target to the `targets` that a switch point or a closing contact concerns. With
    /// `isDeploy` every other radiator gets it too, with reason `system`.
    private func writePlan(to targets: [Radiator], now: Date, isSwitchPoint: Bool, isDeploy: Bool, using hm: HomeManagable) async throws {
        let plan = effectivePlan
        guard let target = plan.planTarget(at: now) else {
            log.warning("Room has no plan target", metadata: ["placeId": "\(placeId)", "date": "\(now)"])
            return
        }
        var ended: [EntityId: RoomContact] = [:]
        for radiator in targets {
            if let contact = await contactJustEndedOffState(of: radiator, now: now, using: hm) {
                ended[radiator.heatingId] = contact
            }
        }
        // A closing concerns only the radiators it ended; only without one is this a deploy.
        let isSystemWrite = isDeploy && ended.isEmpty
        for radiator in targets {
            let reason: HeatingWriteReason
            if isSwitchPoint {
                reason = .plan
            } else if let contact = ended[radiator.heatingId] {
                reason = contact.reason
            } else if isSystemWrite {
                reason = .system
            } else {
                continue
            }
            await HeatingWriteContext.withReason(reason, planTargetInC: target) {
                await radiator.setTarget(target, with: hm)
            }
        }
    }

    /// A switch point while a radiator is off writes nothing to it, but the plan history has to follow the
    /// plan (glossary: plan target): it records the new plan target as a write that was not sent.
    private func recordPlanTargetWhileOff(of offRadiators: [Radiator], at now: Date, using hm: HomeManagable) async {
        guard let target = effectivePlan.planTarget(at: now) else { return }
        for radiator in offRadiators {
            await hm.record(HeatingWrite(timestamp: now, entityId: radiator.targetTemperatureId, reason: .plan, actionName: "setTargetTemperature",
                                         targetTemperatureInC: target, planTargetInC: target, sentToDevice: false))
        }
    }

    /// The radiators that a contact switches off, with the open contact that takes each off first and when:
    /// its open time plus its own delay (window delay for a window, none for the fireplace). A radiator
    /// without an open contact is not listed; an unreachable contact counts as closed.
    private func offStates(using hm: HomeManagable) async -> [(radiator: Radiator, contact: RoomContact, at: Date)] {
        var open: [(contact: RoomContact, at: Date)] = []
        for contact in contacts {
            guard let state = await contact.currentState(with: hm), state.isOpen else { continue }
            open.append((contact, state.since.addingTimeInterval(contact.delay(in: configuration))))
        }
        var result: [(radiator: Radiator, contact: RoomContact, at: Date)] = []
        for radiator in radiators {
            var first: (contact: RoomContact, at: Date)?
            for entry in open where entry.contact.affects(radiator) {
                if first == nil || entry.at < first!.at {
                    first = entry
                }
            }
            if let first {
                result.append((radiator, first.contact, first.at))
            }
        }
        return result
    }

    /// Whether the server switched a radiator that `contact` affects off because of it and has not written it
    /// since. It reads what the server wrote, not the history of the contact: a closed contact the adapter
    /// re-sends says nothing about what the room did.
    private func endedOffState(of contact: RoomContact, using hm: HomeManagable) async -> Bool {
        for radiator in radiators where contact.affects(radiator) {
            if await wasSwitchedOff(radiator, by: contact, using: hm) { return true }
        }
        return false
    }

    private func wasSwitchedOff(_ radiator: Radiator, by contact: RoomContact, using hm: HomeManagable) async -> Bool {
        guard let last = await hm.lastHeatingWrite(of: radiator.heatingId) else { return false }
        return last.isActive == false && last.reason == contact.reason
    }

    /// The contact that closed within the last minute, ending a state the server switched `radiator` off for.
    private func contactJustEndedOffState(of radiator: Radiator, now: Date, using hm: HomeManagable) async -> RoomContact? {
        for contact in contacts where contact.affects(radiator) {
            guard let current = await contact.currentState(with: hm), !current.isOpen, now.timeIntervalSince(current.since) < 60 else { continue }
            if await wasSwitchedOff(radiator, by: contact, using: hm) { return contact }
        }
        return nil
    }
}

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
    /// the fireplace switch when the room follows it.
    public let contacts: [RoomContact]
    /// `nil` for a room without a plan of its own: it follows the standard plan.
    public let plan: HeatingPlan?
    public let configuration: HeatingConfiguration
    /// The room's own temperature sensor; `nil` when the actual value is the mean of the radiators.
    public let roomSensor: EntityId?

    public var triggerEntityIds: Set<EntityId> { Set(contacts.map(\.entityId)) }

    /// The plan this room follows.
    public var effectivePlan: HeatingPlan { plan ?? configuration.standardPlan }

    public init(_ name: String, placeId: PlaceId, radiators: [Radiator], contacts: [RoomContact] = [], plan: HeatingPlan? = nil, roomSensor: EntityId? = nil, configuration: HeatingConfiguration) {
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
        HeatingRoomSources(placeId: placeId,
                           name: placeId,
                           radiators: radiators.map { .init(name: $0.heatingId.name, temperatureId: $0.temperatureId, valvePositionId: $0.valvePositionId, targetTemperatureId: $0.targetTemperatureId) },
                           roomSensor: roomSensor,
                           plan: effectivePlan,
                           followsFireplace: contacts.contains { if case .fireplace = $0 { true } else { false } },
                           contacts: contacts.map { contact in
                               switch contact {
                               case .window(let sensor): .init(source: .window, name: sensor.contactSensorId.name, entityId: sensor.contactSensorId)
                               case .fireplace(let device): .init(source: .fireplace, name: "Kamin", entityId: device.switchId)
                               }
                           })
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
            return await firstOff(using: hm) != nil
        case .sunrise, .sunset:
            return false
        }
    }

    public func execute(using hm: HomeManagable) async throws {
        try await execute(using: hm, now: Date(), sleep: { try await Task.sleep(for: $0) })
    }

    /// Recomputes the room from `now` and the contacts, so a trigger that supersedes a running run (even
    /// one sleeping in the window delay) needs nothing from it.
    ///
    /// - A contact open for the delay: every radiator off, reason `window`. A contact open for less
    ///   waits the rest of the delay and looks again; a run cancelled meanwhile writes nothing.
    /// - No contact open: the plan target. The reason is `plan` in the minute of a switch point, `window`
    ///   when the last contact just closed after the room went off (return to the plan at once, not to an
    ///   old manual value) and `system` otherwise, i.e. after a deploy. A switch point or a deploy while a
    ///   contact is open leaves the radiators off.
    func execute(using hm: HomeManagable, now: Date, sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async throws {
        if let off = await firstOff(using: hm) {
            await recordPlanTargetWhileOff(at: now, using: hm)
            let remaining = off.at.timeIntervalSince(now)
            if remaining > 0 {
                try await sleep(.seconds(remaining))
                // the contacts may have changed while waiting: look again
                guard await firstOff(using: hm) != nil else { return }
            }
            await HeatingWriteContext.withReason(off.contact.reason) {
                for radiator in radiators {
                    await radiator.turnOff(with: hm)
                }
            }
            return
        }

        let plan = effectivePlan
        guard let target = plan.planTarget(at: now) else {
            log.warning("Room \(placeId) has no plan target at \(now)")
            return
        }
        let reason: HeatingWriteReason
        if plan.switchPoint(at: now) != nil {
            reason = .plan
        } else if let ended = await contactJustEndedOffState(now: now, using: hm) {
            reason = ended.reason
        } else {
            reason = .system
        }

        await HeatingWriteContext.withReason(reason, planTargetInC: target) {
            for radiator in radiators {
                await radiator.setTarget(target, with: hm)
            }
        }
    }

    /// A switch point while the room is off writes nothing to the radiators, but the plan history has to
    /// follow the plan (glossary: plan target): it records the new plan target as a write that was not sent.
    private func recordPlanTargetWhileOff(at now: Date, using hm: HomeManagable) async {
        let plan = effectivePlan
        guard plan.switchPoint(at: now) != nil, let target = plan.planTarget(at: now) else { return }
        for radiator in radiators {
            await hm.record(HeatingWrite(timestamp: now, entityId: radiator.targetTemperatureId, reason: .plan, actionName: "setTargetTemperature",
                                         targetTemperatureInC: target, planTargetInC: target, sentToDevice: false))
        }
    }

    /// The open contact that takes the room off first, and when: its open time plus its own delay (window
    /// delay for a window, none for the fireplace). `nil` when no contact is open; an unreachable contact
    /// counts as closed.
    private func firstOff(using hm: HomeManagable) async -> (contact: RoomContact, at: Date)? {
        var first: (contact: RoomContact, at: Date)?
        for contact in contacts {
            guard let state = await contact.currentState(with: hm), state.isOpen else { continue }
            let at = state.since.addingTimeInterval(contact.delay(in: configuration))
            if first == nil || at < first!.at {
                first = (contact, at)
            }
        }
        return first
    }

    /// Whether the server switched a radiator of this room off because of `contact` and has not written it
    /// since. It reads what the server wrote, not the history of the contact: a closed contact the adapter
    /// re-sends says nothing about what the room did.
    private func endedOffState(of contact: RoomContact, using hm: HomeManagable) async -> Bool {
        for radiator in radiators {
            guard let last = await hm.lastHeatingWrite(of: radiator.heatingId),
                  last.isActive == false,
                  last.reason == contact.reason else { continue }
            return true
        }
        return false
    }

    /// The contact that closed within the last minute, ending a state the room went off for.
    private func contactJustEndedOffState(now: Date, using hm: HomeManagable) async -> RoomContact? {
        for contact in contacts {
            guard let current = await contact.currentState(with: hm), !current.isOpen, now.timeIntervalSince(current.since) < 60 else { continue }
            if await endedOffState(of: contact, using: hm) { return contact }
        }
        return nil
    }
}

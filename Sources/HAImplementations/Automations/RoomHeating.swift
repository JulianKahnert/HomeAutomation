//
//  RoomHeating.swift
//  HAImplementations
//

import Foundation
import HAModels

/// Heats one room (glossary: room) after its plan. It is the only writer of the room's radiators.
///
/// It writes the plan target at each switch point and once after a configuration deploy. A plain server
/// start writes nothing, so a manual change at a radiator stays until the next switch point.
public struct RoomHeating: Automatable {
    public var isActive = true
    public let name: String
    public let placeId: PlaceId
    public let radiators: [Radiator]
    /// Contacts that switch the room off while open (glossary: contact): the window contacts of the room.
    public let contacts: [RoomContact]
    /// `nil` for a room without a plan of its own: it follows the standard plan.
    public let plan: HeatingPlan?
    public let configuration: HeatingConfiguration

    public var triggerEntityIds: Set<EntityId> { Set(contacts.map(\.entityId)) }

    /// The plan this room follows.
    public var effectivePlan: HeatingPlan { plan ?? configuration.standardPlan }

    public init(_ name: String, placeId: PlaceId, radiators: [Radiator], contacts: [RoomContact] = [], plan: HeatingPlan? = nil, configuration: HeatingConfiguration) {
        self.name = name
        self.placeId = placeId
        self.radiators = radiators
        self.contacts = contacts
        self.plan = plan
        self.configuration = configuration
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
            // the re-sent closed contacts after a restart must not write the plan over a manual change.
            if contact.isOpen(item) { return true }
            return await endedOffState(of: contact, closedAt: item.timestamp, using: hm)
        case .serverStarted, .sunrise, .sunset:
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
        if let openSince = await earliestOpen(using: hm) {
            let remaining = configuration.windowDelay - now.timeIntervalSince(openSince)
            if remaining > 0 {
                try await sleep(.seconds(remaining))
                // the contacts may have changed while waiting: look again
                guard await earliestOpen(using: hm) != nil else { return }
            }
            await HeatingWriteContext.withReason(.window) {
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
        } else if await contactJustEndedOffState(now: now, using: hm) {
            reason = .window
        } else {
            reason = .system
        }

        await HeatingWriteContext.withReason(reason, planTargetInC: target) {
            for radiator in radiators {
                await radiator.setTarget(target, with: hm)
            }
        }
    }

    /// Since when the earliest of the open contacts is open; `nil` when none is. An unreachable contact counts as closed.
    private func earliestOpen(using hm: HomeManagable) async -> Date? {
        var earliest: Date?
        for contact in contacts {
            guard let state = await contact.currentState(with: hm), state.isOpen else { continue }
            earliest = min(earliest ?? state.since, state.since)
        }
        return earliest
    }

    /// Whether `contact` was open before and long enough for the room to have gone off.
    private func endedOffState(of contact: RoomContact, closedAt: Date, using hm: HomeManagable) async -> Bool {
        guard let previous = await contact.previousState(with: hm), previous.isOpen else { return false }
        return closedAt.timeIntervalSince(previous.since) >= configuration.windowDelay
    }

    /// Whether a contact closed within the last minute, ending a state the room went off for.
    private func contactJustEndedOffState(now: Date, using hm: HomeManagable) async -> Bool {
        for contact in contacts {
            guard let current = await contact.currentState(with: hm), now.timeIntervalSince(current.since) < 60 else { continue }
            if await endedOffState(of: contact, closedAt: current.since, using: hm) { return true }
        }
        return false
    }
}

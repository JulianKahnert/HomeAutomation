//
//  FireplaceTimeout.swift
//  HAImplementations
//

import Foundation
import HAModels

/// Ends the fireplace eight hours after it was switched on, with a push (glossary: fireplace mode).
///
/// The eight hours count from the switch-on time stored in the database, so a server restart does not
/// restart them. The rooms that follow the fireplace return to their plan through their own automation
/// when the switch goes off.
public struct FireplaceTimeout: Automatable {
    public var isActive = true
    public let name: String
    public let fireplace: SwitchDevice
    public let maxDuration: TimeInterval

    public var triggerEntityIds: Set<EntityId> { [fireplace.switchId] }

    public init(_ name: String = "fireplace-timeout", fireplace: SwitchDevice = Fireplace.switchDevice, maxDuration: TimeInterval = Fireplace.maxDuration) {
        self.name = name
        self.fireplace = fireplace
        self.maxDuration = maxDuration
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        guard case .time(let date) = event else { return false }
        return await hasExpired(at: date, using: hm)
    }

    public func execute(using hm: HomeManagable) async throws {
        try await execute(using: hm, now: Date())
    }

    func execute(using hm: HomeManagable, now: Date) async throws {
        // look again: the switch may have gone off since the trigger
        guard await hasExpired(at: now, using: hm) else { return }
        await fireplace.turnOff(with: hm)
        await hm.sendNotification(title: "Kamin aus",
                                  message: "Der Kamin war acht Stunden an und wurde ausgeschaltet. Die Heizkörper folgen wieder dem Plan.",
                                  id: Fireplace.notificationId)
    }

    private func hasExpired(at date: Date, using hm: HomeManagable) async -> Bool {
        let state = await Fireplace.state(of: fireplace.switchId, with: hm)
        guard state.isOn, let since = state.since else { return false }
        return date.timeIntervalSince(since) >= maxDuration
    }
}

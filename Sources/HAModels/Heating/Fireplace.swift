//
//  Fireplace.swift
//  HAModels
//

import Foundation

/// Whether the fireplace burns right now (glossary: fireplace mode).
public struct FireplaceState: Sendable, Equatable {
    public let isOn: Bool
    /// When the fireplace was switched on; `nil` while it is off.
    public let since: Date?
    /// When the server ends the fireplace by itself; `nil` while it is off.
    public let endsAt: Date?

    /// - Parameter endsAt: The end the server named; `nil` derives it from `since` and `Fireplace.maxDuration`.
    public init(isOn: Bool, since: Date? = nil, endsAt: Date? = nil) {
        self.isOn = isOn
        self.since = since
        self.endsAt = endsAt ?? since.map { $0.addingTimeInterval(Fireplace.maxDuration) }
    }

    public init(_ fireplaceSwitch: FireplaceSwitch?) {
        if let fireplaceSwitch, fireplaceSwitch.isOn {
            self.init(isOn: true, since: fireplaceSwitch.timestamp)
        } else {
            self.init(isOn: false)
        }
    }

    public static let off = FireplaceState(isOn: false)
}

/// One switch of the fireplace on or off, as the server stored it. The newest one is the current state.
public struct FireplaceSwitch: Sendable, Equatable, Codable {
    public let timestamp: Date
    public let isOn: Bool

    public init(timestamp: Date, isOn: Bool) {
        self.timestamp = timestamp
        self.isOn = isOn
    }
}

/// Persistence of the fireplace switches; implemented by the server's database.
public protocol FireplaceRepository: Sendable {
    func add(_ fireplaceSwitch: FireplaceSwitch) async throws
    /// The newest switch; `nil` when the fireplace was never switched.
    func latest() async throws -> FireplaceSwitch?
    /// The switches in `startDate ..< endDate` plus the last one before `startDate`, oldest first.
    func switches(from startDate: Date, to endDate: Date) async throws -> [FireplaceSwitch]
}

/// The fireplace mode: a state the server keeps itself, switched only from the FlowKit Controller app (the
/// Heizung tab and the push action "Kamin an?") and ended by `FireplaceTimeout`. Rooms read it like a window
/// contact (`RoomContact.fireplace`); a change reaches them as `HomeEvent.fireplaceChanged`.
public enum Fireplace {
    /// The fireplace ends this long after it was switched on.
    public static let maxDuration: TimeInterval = 2 * 3600

    /// Stands for the fireplace where the heating needs an `EntityId` (the contact of a room, its history in
    /// the room detail). No HomeKit entity has it.
    public static let stateId = EntityId(placeId: "Server", name: "Kamin", characteristicsName: nil, characteristic: .switcher)

    /// Category of the push "Kamin an?"; the app registers its action under this name.
    public static let notificationCategory = "FIREPLACE_ASK"
    /// The action of that category that switches the fireplace on.
    public static let switchOnActionId = "FIREPLACE_ON"
    /// Collapse id of the reminder "Kamin an?"; apart from `notificationId` so the end push does not count against its rate limit.
    public static let reminderNotificationId = "fireplace-reminder"
    /// Collapse id of the fireplace pushes, so a newer one replaces an older.
    public static let notificationId = "fireplace"

    /// The state the server holds. It does not depend on HomeKit: a degraded HomeKit stops the radiator writes,
    /// not the fire.
    public static func state(with hm: HomeManagable) async -> FireplaceState {
        FireplaceState(await hm.lastFireplaceSwitch())
    }

    /// Switches the fireplace on or off. Asking for the state it already has changes nothing, so a second "on"
    /// does not restart `maxDuration`. The answer is the new state, effective at once.
    @discardableResult
    public static func set(isOn: Bool, with hm: HomeManagable, now: Date = Date()) async -> FireplaceState {
        if let changed = await hm.switchFireplace(isOn: isOn, at: now) {
            return FireplaceState(changed)
        }
        return await state(with: hm)
    }
}

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

    public static let off = FireplaceState(isOn: false)
}

/// The fireplace mode: a server-owned switch entity (`Fireplace.stateId`), set from the FlowKit Controller app
/// (the Heizung tab and the push action "Kamin an?") through `PUT /entities/state` with origin `app`, and ended
/// by `FireplaceTimeout` with origin `server`. Rooms read it like a window contact (`RoomContact.fireplace`); a
/// change reaches them as an ordinary `HomeEvent.change`.
public enum Fireplace {
    /// The fireplace ends this long after it was switched on.
    public static let maxDuration: TimeInterval = 2 * 3600

    /// The fireplace entity: server-owned, a switch (on = burning). The app may set it: a switch is a kind the app may set (``ValueDescriptor/isSettableFromApp``).
    public static let stateId = EntityId.serverOwned(name: "fireplace", characteristic: .switcher)

    /// Category of the push "Kamin an?"; the app registers its action under this name.
    public static let notificationCategory = "FIREPLACE_ASK"
    /// The action of that category that switches the fireplace on.
    public static let switchOnActionId = "FIREPLACE_ON"
    /// Collapse id of the reminder "Kamin an?"; apart from `notificationId` so the end push does not count against its rate limit.
    public static let reminderNotificationId = "fireplace-reminder"
    /// Collapse id of the fireplace pushes, so a newer one replaces an older.
    public static let notificationId = "fireplace"

    /// The state the server holds, since the last change of the entity (a repeated value keeps it). It does not
    /// depend on HomeKit: a degraded HomeKit stops the radiator writes, not the fire.
    /// - Throws: Any failure of reading the state; only an entity the server never held is `.off`.
    public static func state(with hm: HomeManagable) async throws -> FireplaceState {
        let item: EntityStorageItem
        do {
            item = try await hm.getCurrentEntity(with: stateId)
        } catch OptionalError.notFound {
            return .off
        }
        guard item.isDeviceOn == true else { return .off }
        return FireplaceState(isOn: true, since: item.timestamp)
    }
}

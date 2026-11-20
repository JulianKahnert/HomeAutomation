//
//  Fireplace.swift
//  HAModels
//

import Foundation

/// What the fireplace switch says right now (glossary: fireplace mode).
public struct FireplaceState: Sendable, Equatable {
    public let isOn: Bool
    /// When the switch went on; `nil` while it is off.
    public let since: Date?

    public init(isOn: Bool, since: Date? = nil) {
        self.isOn = isOn
        self.since = since
    }

    /// When the server switches the fireplace off by itself; `nil` while it is off.
    public var endsAt: Date? {
        since.map { $0.addingTimeInterval(Fireplace.maxDuration) }
    }

    public static let off = FireplaceState(isOn: false)
}

/// The fireplace: the persistent Homebridge switch `Keller_Kamin_switcher`. Rooms read it like a window
/// contact (`RoomContact.fireplace`), the server switches it on request of the Heizung tab and the push action.
public enum Fireplace {
    /// The fireplace ends this long after it was switched on.
    public static let maxDuration: TimeInterval = 8 * 3600

    /// The switch in HomeKit (adapter id `Keller_Kamin_switcher`).
    public static let switchId = EntityId(placeId: "Keller", name: "Kamin", characteristicsName: nil, characteristic: .switcher)

    public static var switchDevice: SwitchDevice {
        SwitchDevice(switchId: switchId, brightnessId: nil, colorTemperatureId: nil, rgbId: nil)
    }

    /// Category of the push "Kamin an?"; the app registers its action under this name.
    public static let notificationCategory = "FIREPLACE_ASK"
    /// The action of that category that switches the fireplace on.
    public static let switchOnActionId = "FIREPLACE_ON"
    /// Collapse id of the fireplace pushes, so a newer one replaces an older.
    public static let notificationId = "fireplace"

    /// The state of the switch `switchId`. An unreachable switch (its state cannot be read) is off.
    ///
    /// The start time comes from the database, not from the cache: after a restart the adapter's resync
    /// refreshes the cache with a new timestamp, the database still holds when the switch went on.
    public static func state(of switchId: EntityId, with hm: HomeManagable) async -> FireplaceState {
        guard let current = try? await hm.getCurrentEntity(with: switchId), current.isDeviceOn == true else { return .off }
        if let stored = await hm.getStoredEntity(with: switchId), stored.isDeviceOn == true {
            return FireplaceState(isOn: true, since: stored.timestamp)
        }
        return FireplaceState(isOn: true, since: current.timestamp)
    }

    public static func state(with hm: HomeManagable) async -> FireplaceState {
        await state(of: switchId, with: hm)
    }

    /// Switches the fireplace on or off, as the Heizung tab and the push action ask. Asking for the state
    /// it already has changes nothing, so a second "on" does not restart the eight hours. The answer is the
    /// state the switch will have, because HomeKit reports the change a moment later.
    public static func set(isOn: Bool, with hm: HomeManagable, now: Date = Date()) async -> FireplaceState {
        let current = await state(with: hm)
        guard current.isOn != isOn else { return current }
        if isOn {
            await switchDevice.turnOn(with: hm)
            return FireplaceState(isOn: true, since: now)
        } else {
            await switchDevice.turnOff(with: hm)
            return .off
        }
    }
}

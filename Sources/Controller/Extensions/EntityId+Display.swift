//
//  EntityId+Display.swift
//  Controller
//

import HAModels

extension EntityId {
    /// "Eve Motion (Arbeitszimmer)" — the room disambiguates devices in lists that span rooms.
    var displayName: String {
        "\(name) (\(placeId))"
    }

    /// "Motion Sensor (Arbeitszimmer)"
    var kindInRoom: String {
        "\(characteristicType.displayName) (\(placeId))"
    }
}

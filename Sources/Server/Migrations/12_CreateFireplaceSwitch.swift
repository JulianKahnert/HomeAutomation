//
//  12_CreateFireplaceSwitch.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAModels

/// The fireplace mode as the server's own state: one row per switch, the newest is the current state.
///
/// It carries the history of the Homebridge dummy switch `Keller_Kamin_switcher` over, which held the
/// fireplace before: every change of its on/off state becomes a row, so the room detail keeps showing the
/// fireplace events of the past days. The switch's rows in `entityItems` stay untouched; nothing reads them
/// for the fireplace any more.
struct CreateFireplaceSwitch: AsyncMigration {
    /// The former fireplace switch in HomeKit.
    static let legacySwitch = (placeId: "Keller", name: "Kamin", characteristicType: "switcher")

    func prepare(on database: Database) async throws {
        try await database.schema(FireplaceSwitchDbItem.schema)
            .id()
            .field("timestamp", .datetime, .required)
            .field("isOn", .bool, .required)
            .create()

        let legacy = try await EntityStorageDbItem.query(on: database)
            .filter(\.$entityPlaceId == Self.legacySwitch.placeId)
            .filter(\.$entityServiceName == Self.legacySwitch.name)
            .filter(\.$entityCharacteristicType == Self.legacySwitch.characteristicType)
            .sort(\.$timestamp, .ascending)
            .all()
        for fireplaceSwitch in Self.switches(from: legacy.compactMap { item in item.isDeviceOn.map { (item.timestamp, $0) } }) {
            try await FireplaceSwitchDbItem(fireplaceSwitch).create(on: database)
        }
    }

    func revert(on database: Database) async throws {
        try await database.schema(FireplaceSwitchDbItem.schema).delete()
    }

    /// The changes of the on/off state, oldest first; a repeated value (an adapter resync) is no switch, and an
    /// "off" before the first "on" says nothing.
    static func switches(from states: [(timestamp: Date, isOn: Bool)]) -> [FireplaceSwitch] {
        var result: [FireplaceSwitch] = []
        for state in states.sorted(by: { $0.timestamp < $1.timestamp }) where state.isOn != (result.last?.isOn ?? false) {
            result.append(FireplaceSwitch(timestamp: state.timestamp, isOn: state.isOn))
        }
        return result
    }
}

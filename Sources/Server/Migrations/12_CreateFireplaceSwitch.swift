//
//  12_CreateFireplaceSwitch.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAModels
import SQLKit

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

        let legacy = try await legacyStates(on: database)
        for fireplaceSwitch in Self.switches(from: legacy) {
            try await FireplaceSwitchDbItem(fireplaceSwitch).create(on: database)
        }
    }

    /// The on/off rows of the former switch in the old wide table, oldest first.
    private func legacyStates(on database: Database) async throws -> [(timestamp: Date, isOn: Bool)] {
        guard let sql = database as? SQLDatabase else { return [] }
        let rows = try await sql.raw("""
            SELECT \(ident: "timestamp"), \(ident: "isDeviceOn") FROM \(ident: LegacyEntityItems.schema)
            WHERE \(ident: "entityPlaceId") = \(bind: Self.legacySwitch.placeId)
              AND \(ident: "entityServiceName") = \(bind: Self.legacySwitch.name)
              AND \(ident: "entityCharacteristicType") = \(bind: Self.legacySwitch.characteristicType)
              AND \(ident: "isDeviceOn") IS NOT NULL
            ORDER BY \(ident: "timestamp") ASC
            """).all()
        return try rows.map { try ($0.decode(column: "timestamp", as: Date.self), $0.decode(column: "isDeviceOn", as: Bool.self)) }
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

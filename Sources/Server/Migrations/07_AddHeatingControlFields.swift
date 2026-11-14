//
//  07_AddHeatingControlFields.swift
//  HomeAutomationServer
//

import Fluent

/// Adds the thermostat target temperature, target mode and Eve valve position (percent) to the entityItems table.
struct AddHeatingControlFields: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(EntityStorageDbItem.schema)
            .field("targetTemperatureInC", .double)
            .field("heatingMode", .int)
            .field("valvePositionPercent", .int)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(EntityStorageDbItem.schema)
            .deleteField("targetTemperatureInC")
            .deleteField("heatingMode")
            .deleteField("valvePositionPercent")
            .update()
    }
}

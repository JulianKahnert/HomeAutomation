//
//  07_AddHeatingControlFields.swift
//  HomeAutomationServer
//

import Fluent

/// Adds the thermostat target temperature, target mode and Eve valve position (percent) to the entityItems table.
struct AddHeatingControlFields: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(LegacyEntityItems.schema)
            .field("targetTemperatureInC", .double)
            // Fluent maps .int8/.uint8 to INT on MySQL, so the narrow types are spelled out.
            .field("heatingMode", .custom("TINYINT"))
            .field("valvePositionPercent", .custom("TINYINT UNSIGNED"))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(LegacyEntityItems.schema)
            .deleteField("targetTemperatureInC")
            .deleteField("heatingMode")
            .deleteField("valvePositionPercent")
            .update()
    }
}

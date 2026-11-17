//
//  10_AddTemperatureCalibration.swift
//  HomeAutomationServer
//

import Fluent

/// Adds the thermostat temperature offset (Matter `LocalTemperatureCalibration`, in Celsius) to the entityItems table.
struct AddTemperatureCalibration: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(EntityStorageDbItem.schema)
            .field("temperatureCalibrationInC", .double)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(EntityStorageDbItem.schema)
            .deleteField("temperatureCalibrationInC")
            .update()
    }
}

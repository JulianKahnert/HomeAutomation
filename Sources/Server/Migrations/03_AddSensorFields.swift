//
//  03_AddSensorFields.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 27.12.25.
//

import Fluent

/// Migration to add missing sensor fields to the entityItems table
/// Adds support for temperature, humidity, CO2, PM2.5, air quality, brightness, color temperature, color, and valve state
struct AddSensorFields: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(EntityStorageDbItem.schema)
            .field("brightness", .int)
            .field("colorTemperature", .float)
            .field("colorRed", .float)
            .field("colorGreen", .float)
            .field("colorBlue", .float)
            .field("temperatureInC", .double)
            .field("relativeHumidity", .double)
            .field("carbonDioxideSensorId", .int)
            .field("pmDensity", .double)
            .field("airQuality", .int)
            .field("valveOpen", .bool)
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(EntityStorageDbItem.schema)
            .deleteField("brightness")
            .deleteField("colorTemperature")
            .deleteField("colorRed")
            .deleteField("colorGreen")
            .deleteField("colorBlue")
            .deleteField("temperatureInC")
            .deleteField("relativeHumidity")
            .deleteField("carbonDioxideSensorId")
            .deleteField("pmDensity")
            .deleteField("airQuality")
            .deleteField("valveOpen")
            .update()
    }
}

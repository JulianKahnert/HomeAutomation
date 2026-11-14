//
//  08_CreateWeatherHour.swift
//  HomeAutomationServer
//

import Fluent

struct CreateWeatherHour: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(WeatherHour.schema)
            .id()
            .field("locationKey", .string, .required)
            .field("hour", .datetime, .required)
            .field("temperatureInC", .double)
            .field("fetchedAt", .datetime, .required)
            .field("data", .custom("TEXT"), .required)
            .unique(on: "locationKey", "hour")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(WeatherHour.schema).delete()
    }
}

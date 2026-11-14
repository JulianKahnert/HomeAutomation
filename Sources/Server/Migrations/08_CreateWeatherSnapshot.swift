//
//  08_CreateWeatherSnapshot.swift
//  HomeAutomationServer
//

import Fluent

struct CreateWeatherSnapshot: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(WeatherSnapshot.schema)
            .id()
            .field("locationKey", .string, .required)
            .field("fetchedAt", .datetime, .required)
            .field("json", .custom("LONGTEXT"), .required)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(WeatherSnapshot.schema).delete()
    }
}

//
//  08_CreateWeatherHour.swift
//  HomeAutomationServer
//

import Fluent

/// One row per location and hour; the primary key `(locationKey, hour)` is the upsert key.
/// FLOAT (4 bytes) is ample for weather values with one decimal; the narrow integer types are spelled
/// out because Fluent maps `.int8`/`.uint8` to INT on MySQL.
struct CreateWeatherHour: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(WeatherHour.schema)
            .field("locationKey", .custom("VARCHAR(64)"), .required)
            .field("hour", .datetime, .required)
            .field("fetchedAt", .datetime, .required)
            .field("temperature2mC", .float)
            .field("apparentTemperatureC", .float)
            .field("relativeHumidity2mPercent", .custom("TINYINT UNSIGNED"))
            .field("dewPoint2mC", .float)
            .field("precipitationMm", .float)
            .field("cloudCoverPercent", .custom("TINYINT UNSIGNED"))
            .field("windSpeed10mKmh", .float)
            .field("windDirection10mDeg", .custom("SMALLINT UNSIGNED"))
            .field("shortwaveRadiationWm2", .float)
            .field("directRadiationWm2", .float)
            .field("diffuseRadiationWm2", .float)
            .field("directNormalIrradianceWm2", .float)
            .field("sunshineDurationS", .float)
            .field("isDay", .bool)
            .compositeIdentifier(over: "locationKey", "hour")
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(WeatherHour.schema).delete()
    }
}

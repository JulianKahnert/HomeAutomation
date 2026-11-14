//
//  WeatherHour.swift
//  HomeAutomationServer
//

import Fluent
import Foundation

/// One hour of weather for one location, unique on `(locationKey, hour)` and overwritten by every newer fetch.
/// Not touched by `DatabaseCleanupJob`: about 9k small rows per year are kept on purpose.
final class WeatherHour: Model, @unchecked Sendable {
    static let schema = "weatherHours"

    @ID(key: .id)
    var id: UUID?

    /// `latitude,longitude` as sent to the weather service.
    @Field(key: "locationKey")
    var locationKey: String

    /// Start of the hour (UTC).
    @Field(key: "hour")
    var hour: Date

    @Field(key: "temperatureInC")
    var temperatureInC: Double?

    @Field(key: "fetchedAt")
    var fetchedAt: Date

    /// JSON object with every requested variable of this hour as received from Open-Meteo.
    @Field(key: "data")
    var data: String

    init() { }

    init(locationKey: String, hour: Date, temperatureInC: Double?, fetchedAt: Date, data: String) {
        self.locationKey = locationKey
        self.hour = hour
        self.temperatureInC = temperatureInC
        self.fetchedAt = fetchedAt
        self.data = data
    }
}

/// Plain value of a `WeatherHour`.
struct WeatherHourValue: Sendable, Equatable {
    let locationKey: String
    let hour: Date
    let temperatureInC: Double?
    let fetchedAt: Date
    let data: String
}

protocol WeatherHourStoring: Sendable {
    /// Inserts new hours and overwrites existing ones of the same `(locationKey, hour)`.
    func upsert(_ values: [WeatherHourValue]) async throws
    /// Hours of one location, newest first; `cursor` returns only hours before it.
    func history(locationKey: String, startDate: Date?, endDate: Date?, cursor: Date?, limit: Int) async throws -> [WeatherHourValue]
}

struct WeatherHourDbRepository: WeatherHourStoring {
    let database: @Sendable () -> any Database

    func upsert(_ values: [WeatherHourValue]) async throws {
        let db = database()
        for value in values {
            let existing = try await WeatherHour.query(on: db)
                .filter(\.$locationKey == value.locationKey)
                .filter(\.$hour == value.hour)
                .first()
            let row = existing ?? WeatherHour(locationKey: value.locationKey, hour: value.hour, temperatureInC: nil, fetchedAt: value.fetchedAt, data: value.data)
            row.temperatureInC = value.temperatureInC
            row.fetchedAt = value.fetchedAt
            row.data = value.data
            try await row.save(on: db)
        }
    }

    func history(locationKey: String, startDate: Date?, endDate: Date?, cursor: Date?, limit: Int) async throws -> [WeatherHourValue] {
        var query = WeatherHour.query(on: database()).filter(\.$locationKey == locationKey)
        if let startDate { query = query.filter(\.$hour >= startDate) }
        if let endDate { query = query.filter(\.$hour < endDate) }
        if let cursor { query = query.filter(\.$hour < cursor) }
        return try await query.sort(\.$hour, .descending).limit(limit).all().map {
            WeatherHourValue(locationKey: $0.locationKey, hour: $0.hour, temperatureInC: $0.temperatureInC, fetchedAt: $0.fetchedAt, data: $0.data)
        }
    }
}

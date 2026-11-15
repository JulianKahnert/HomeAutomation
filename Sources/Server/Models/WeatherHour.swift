//
//  WeatherHour.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import SQLKit
import Vapor

/// One hour of Open-Meteo weather for one location, one column per requested hourly variable.
/// Units are Open-Meteo's defaults and part of the column names. Radiation, precipitation and
/// sunshine refer to the hour before `hour`.
///
/// Key `(locationKey, hour)`: every fetch overwrites the hours it contains, so a past hour ends up
/// with the newest (observed) value instead of an old forecast. No job deletes these rows; they are
/// kept indefinitely for now.
struct WeatherHour: Sendable, Equatable {
    static let schema = "weatherHours"

    /// `latitude,longitude` as sent to the weather service.
    var locationKey: String
    /// Start of the hour, UTC.
    var hour: Date
    var fetchedAt: Date
    var temperature2mC: Double?
    var apparentTemperatureC: Double?
    var relativeHumidity2mPercent: Int?
    var dewPoint2mC: Double?
    var precipitationMm: Double?
    var cloudCoverPercent: Int?
    var windSpeed10mKmh: Double?
    var windDirection10mDeg: Int?
    var shortwaveRadiationWm2: Double?
    var directRadiationWm2: Double?
    var diffuseRadiationWm2: Double?
    var directNormalIrradianceWm2: Double?
    var sunshineDurationS: Double?
    var isDay: Bool?
}

protocol WeatherHourStoring: Sendable {
    /// Inserts new hours and overwrites existing ones of the same `(locationKey, hour)`.
    func upsert(_ hours: [WeatherHour]) async throws
}

struct WeatherHourDbRepository: WeatherHourStoring {
    let database: @Sendable () -> any Database

    /// `(column, value)` in table order; the one list keeps insert and update in step.
    static func columns(of hour: WeatherHour) -> [(String, any Encodable & Sendable)] {
        [
            ("locationKey", hour.locationKey), ("hour", hour.hour), ("fetchedAt", hour.fetchedAt),
            ("temperature2mC", hour.temperature2mC), ("apparentTemperatureC", hour.apparentTemperatureC),
            ("relativeHumidity2mPercent", hour.relativeHumidity2mPercent), ("dewPoint2mC", hour.dewPoint2mC),
            ("precipitationMm", hour.precipitationMm), ("cloudCoverPercent", hour.cloudCoverPercent),
            ("windSpeed10mKmh", hour.windSpeed10mKmh), ("windDirection10mDeg", hour.windDirection10mDeg),
            ("shortwaveRadiationWm2", hour.shortwaveRadiationWm2), ("directRadiationWm2", hour.directRadiationWm2),
            ("diffuseRadiationWm2", hour.diffuseRadiationWm2), ("directNormalIrradianceWm2", hour.directNormalIrradianceWm2),
            ("sunshineDurationS", hour.sunshineDurationS), ("isDay", hour.isDay)
        ]
    }

    func upsert(_ hours: [WeatherHour]) async throws {
        guard let first = hours.first else { return }
        guard let sql = database() as? SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL queries")
        }
        let names = Self.columns(of: first).map(\.0)
        let insert = sql.insert(into: WeatherHour.schema).columns(names)
        for hour in hours {
            insert.values(Self.columns(of: hour).map { SQLBind($0.1) })
        }
        try await insert
            .onConflict(do: { update in
                names.filter { $0 != "locationKey" && $0 != "hour" }.reduce(update) { $0.set(excludedValueOf: $1) }
            })
            .run()
    }

    /// Hours of one location, oldest first.
    func hours(locationKey: String) async throws -> [WeatherHour] {
        guard let sql = database() as? SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL queries")
        }
        return try await sql.select().columns("*").from(WeatherHour.schema)
            .where("locationKey", .equal, locationKey)
            .orderBy("hour")
            .all()
            .map { row in
                try WeatherHour(locationKey: row.decode(column: "locationKey", as: String.self),
                                hour: row.decode(column: "hour", as: Date.self),
                                fetchedAt: row.decode(column: "fetchedAt", as: Date.self),
                                temperature2mC: row.decode(column: "temperature2mC", as: Double?.self),
                                apparentTemperatureC: row.decode(column: "apparentTemperatureC", as: Double?.self),
                                relativeHumidity2mPercent: row.decode(column: "relativeHumidity2mPercent", as: Int?.self),
                                dewPoint2mC: row.decode(column: "dewPoint2mC", as: Double?.self),
                                precipitationMm: row.decode(column: "precipitationMm", as: Double?.self),
                                cloudCoverPercent: row.decode(column: "cloudCoverPercent", as: Int?.self),
                                windSpeed10mKmh: row.decode(column: "windSpeed10mKmh", as: Double?.self),
                                windDirection10mDeg: row.decode(column: "windDirection10mDeg", as: Int?.self),
                                shortwaveRadiationWm2: row.decode(column: "shortwaveRadiationWm2", as: Double?.self),
                                directRadiationWm2: row.decode(column: "directRadiationWm2", as: Double?.self),
                                diffuseRadiationWm2: row.decode(column: "diffuseRadiationWm2", as: Double?.self),
                                directNormalIrradianceWm2: row.decode(column: "directNormalIrradianceWm2", as: Double?.self),
                                sunshineDurationS: row.decode(column: "sunshineDurationS", as: Double?.self),
                                isDay: row.decode(column: "isDay", as: Bool?.self))
            }
    }
}

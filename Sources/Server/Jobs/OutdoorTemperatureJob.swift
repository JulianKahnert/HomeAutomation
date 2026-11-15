//
//  OutdoorTemperatureJob.swift
//  HomeAutomationServer
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HAModels
import Logging
import Shared

/// Stores the Open-Meteo weather of the configured location once an hour as one `weatherHours` row
/// per hour, so heating data can be compared with the weather.
struct OutdoorTemperatureJob: Job, Log {
    let location: Location
    let hours: any WeatherHourStoring
    var fetch: @Sendable (URL) async throws -> Data = { url in
        try await URLSession.shared.data(from: url).0
    }

    /// Hourly variables requested; tilted irradiance is computed later from the radiation components.
    static let hourlyVariables = [
        "temperature_2m", "apparent_temperature", "relative_humidity_2m", "dew_point_2m", "precipitation", "cloud_cover",
        "wind_speed_10m", "wind_direction_10m", "shortwave_radiation", "direct_radiation", "diffuse_radiation",
        "direct_normal_irradiance", "sunshine_duration", "is_day"
    ].joined(separator: ",")

    static func locationKey(for location: Location) -> String {
        "\(location.latitude),\(location.longitude)"
    }

    /// `past_days`/`forecast_days` let later fetches fill gaps and replace forecasts with newer values.
    static func url(for location: Location) -> URL {
        URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(location.latitude)&longitude=\(location.longitude)&hourly=\(hourlyVariables)&past_days=1&forecast_days=2&timezone=UTC")!
    }

    /// Fetches the weather and upserts one row per hour; returns the stored hours.
    @discardableResult
    func recordOnce(now: Date = Date()) async throws -> [WeatherHour] {
        let data = try await fetch(Self.url(for: location))
        let hours = try Self.parse(data, locationKey: Self.locationKey(for: location), fetchedAt: now)
        try await self.hours.upsert(hours)
        return hours
    }

    /// Throws for a response without hourly data, so an error page is never stored.
    static func parse(_ data: Data, locationKey: String, fetchedAt: Date) throws -> [WeatherHour] {
        let hourly = try JSONDecoder().decode(Response.self, from: data).hourly
        let formatter = ISO8601DateFormatter()
        return try hourly.time.enumerated().map { index, time in
            // `timezone=UTC` sends "2026-11-14T11:00" without seconds and zone.
            guard let hour = formatter.date(from: time + ":00Z") else {
                throw URLError(.cannotParseResponse)
            }
            func value(_ series: [Double?]?) -> Double? {
                guard let series, index < series.count else { return nil }
                return series[index]
            }
            return WeatherHour(locationKey: locationKey, hour: hour, fetchedAt: fetchedAt,
                               temperature2mC: value(hourly.temperature2m),
                               apparentTemperatureC: value(hourly.apparentTemperature),
                               relativeHumidity2mPercent: value(hourly.relativeHumidity2m).map { Int($0.rounded()) },
                               dewPoint2mC: value(hourly.dewPoint2m),
                               precipitationMm: value(hourly.precipitation),
                               cloudCoverPercent: value(hourly.cloudCover).map { Int($0.rounded()) },
                               windSpeed10mKmh: value(hourly.windSpeed10m),
                               windDirection10mDeg: value(hourly.windDirection10m).map { Int($0.rounded()) },
                               shortwaveRadiationWm2: value(hourly.shortwaveRadiation),
                               directRadiationWm2: value(hourly.directRadiation),
                               diffuseRadiationWm2: value(hourly.diffuseRadiation),
                               directNormalIrradianceWm2: value(hourly.directNormalIrradiance),
                               sunshineDurationS: value(hourly.sunshineDuration),
                               isDay: value(hourly.isDay).map { $0 != 0 })
        }
    }

    private struct Response: Decodable {
        let hourly: Hourly
    }

    private struct Hourly: Decodable {
        let time: [String]
        let temperature2m, apparentTemperature, relativeHumidity2m, dewPoint2m, precipitation, cloudCover: [Double?]?
        let windSpeed10m, windDirection10m, shortwaveRadiation, directRadiation, diffuseRadiation: [Double?]?
        let directNormalIrradiance, sunshineDuration, isDay: [Double?]?

        enum CodingKeys: String, CodingKey {
            case time
            case temperature2m = "temperature_2m", apparentTemperature = "apparent_temperature"
            case relativeHumidity2m = "relative_humidity_2m", dewPoint2m = "dew_point_2m", precipitation
            case cloudCover = "cloud_cover", windSpeed10m = "wind_speed_10m", windDirection10m = "wind_direction_10m"
            case shortwaveRadiation = "shortwave_radiation", directRadiation = "direct_radiation"
            case diffuseRadiation = "diffuse_radiation", directNormalIrradiance = "direct_normal_irradiance"
            case sunshineDuration = "sunshine_duration", isDay = "is_day"
        }
    }

    func run() async {
        log.info("Starting OutdoorTemperatureJob - will run every hour")
        while !Task.isCancelled {
            do {
                try await recordOnce()
            } catch {
                log.error("Failed to record weather: \(error)")
            }
            try? await Task.sleep(for: .hours(1))
        }
    }
}

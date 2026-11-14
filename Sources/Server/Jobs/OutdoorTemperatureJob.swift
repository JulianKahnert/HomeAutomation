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

/// Stores the hourly weather of the configured location once an hour, one row per hour, so heating data can be compared with the weather.
struct OutdoorTemperatureJob: Job, Log {
    let location: Location
    let weather: any WeatherHourStoring
    var fetch: @Sendable (URL) async throws -> Data = { url in
        try await URLSession.shared.data(from: url).0
    }

    /// Hourly variables stored per hour; tilted irradiance is computed later from the radiation components.
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

    /// One row per hour of an Open-Meteo `hourly` block (forecast and archive share the format); `data` holds all variables of the hour.
    static func parseHours(_ data: Data, location: Location, fetchedAt: Date) throws -> [WeatherHourValue] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hourly = root["hourly"] as? [String: Any],
              let times = hourly["time"] as? [String] else {
            throw URLError(.cannotParseResponse)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let key = locationKey(for: location)

        return try times.enumerated().compactMap { index, time -> WeatherHourValue? in
            guard let hour = formatter.date(from: time) else { return nil }
            var values: [String: Any] = [:]
            for (name, series) in hourly where name != "time" {
                if let array = series as? [Any], index < array.count, !(array[index] is NSNull) {
                    values[name] = array[index]
                }
            }
            let json = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys])
            return WeatherHourValue(locationKey: key,
                                    hour: hour,
                                    temperatureInC: (values["temperature_2m"] as? NSNumber)?.doubleValue,
                                    fetchedAt: fetchedAt,
                                    data: String(decoding: json, as: UTF8.self))
        }
    }

    /// Fetches the weather and upserts every hour of the response; returns the stored hours.
    @discardableResult
    func recordOnce(now: Date = Date()) async throws -> [WeatherHourValue] {
        let data = try await fetch(Self.url(for: location))
        let hours = try Self.parseHours(data, location: location, fetchedAt: now)
        try await weather.upsert(hours)
        return hours
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

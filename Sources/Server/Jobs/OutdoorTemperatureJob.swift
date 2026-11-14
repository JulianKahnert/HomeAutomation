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

/// Stores the raw Open-Meteo response of the configured location once an hour, so heating data can be compared with the weather.
struct OutdoorTemperatureJob: Job, Log {
    let location: Location
    let snapshots: any WeatherSnapshotStoring
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

    /// Fetches the weather and stores the raw response as one snapshot; returns the stored JSON.
    @discardableResult
    func recordOnce(now: Date = Date()) async throws -> String {
        let data = try await fetch(Self.url(for: location))
        // Reject a response without hourly data, so an error page is never stored as a snapshot.
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any], root["hourly"] is [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        let json = String(decoding: data, as: UTF8.self)
        try await snapshots.add(locationKey: Self.locationKey(for: location), fetchedAt: now, json: json)
        return json
    }

    func run() async {
        log.info("Starting OutdoorTemperatureJob - will run every hour")
        while !Task.isCancelled {
            do {
                try await recordOnce()
            } catch {
                log.error("Failed to record weather snapshot: \(error)")
            }
            try? await Task.sleep(for: .hours(1))
        }
    }
}

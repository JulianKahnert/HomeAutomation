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

/// Records the outdoor temperature of the configured location once an hour, so heating data can be compared with the weather.
struct OutdoorTemperatureJob: Job, Log {
    /// Place and name of the recorded entity; query `/entities/history` with these and `characteristicType=outdoorTemperature`.
    static let entityId = EntityId(placeId: "Outdoor", name: "Open-Meteo", characteristicsName: nil, characteristic: .outdoorTemperature)

    let location: Location
    let storage: any StorageRepository
    let snapshots: any WeatherSnapshotStoring
    var fetch: @Sendable (URL) async throws -> Data = { url in
        try await URLSession.shared.data(from: url).0
    }

    /// Hourly variables stored in the raw snapshot; tilted irradiance is computed later from the radiation components.
    static let hourlyVariables = [
        "temperature_2m", "apparent_temperature", "relative_humidity_2m", "dew_point_2m", "precipitation", "cloud_cover",
        "wind_speed_10m", "wind_direction_10m", "shortwave_radiation", "direct_radiation", "diffuse_radiation",
        "direct_normal_irradiance", "sunshine_duration", "is_day"
    ].joined(separator: ",")

    static func locationKey(for location: Location) -> String {
        "\(location.latitude),\(location.longitude)"
    }

    static func url(for location: Location) -> URL {
        URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(location.latitude)&longitude=\(location.longitude)&current=temperature_2m&hourly=\(hourlyVariables)&past_days=1&forecast_days=2&timezone=UTC")!
    }

    /// Reads `current.temperature_2m` (degrees Celsius) from an Open-Meteo forecast response.
    static func parseTemperature(_ data: Data) throws -> Double {
        struct Response: Decodable {
            struct Current: Decodable { let temperature_2m: Double } // swiftlint:disable:this identifier_name
            let current: Current
        }
        return try JSONDecoder().decode(Response.self, from: data).current.temperature_2m
    }

    /// Fetches the current temperature and stores it; returns the stored item.
    @discardableResult
    func recordOnce(now: Date = Date()) async throws -> EntityStorageItem {
        let data = try await fetch(Self.url(for: location))
        let celsius = try Self.parseTemperature(data)
        let item = EntityStorageItem(entityId: Self.entityId, timestamp: now, temperatureInC: .init(value: celsius, unit: .celsius))
        try await storage.add(item)
        // The raw response is stored as received; past and forecast hours let gaps be reconstructed later.
        try await snapshots.add(locationKey: Self.locationKey(for: location), fetchedAt: now, json: String(decoding: data, as: UTF8.self))
        return item
    }

    func run() async {
        log.info("Starting OutdoorTemperatureJob - will run every hour")
        while !Task.isCancelled {
            do {
                try await recordOnce()
            } catch {
                log.error("Failed to record outdoor temperature: \(error)")
            }
            try? await Task.sleep(for: .hours(1))
        }
    }
}

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
    var fetch: @Sendable (URL) async throws -> Data = { url in
        try await URLSession.shared.data(from: url).0
    }

    static func url(for location: Location) -> URL {
        URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(location.latitude)&longitude=\(location.longitude)&current=temperature_2m")!
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

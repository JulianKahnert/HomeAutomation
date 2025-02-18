//
//  GardenWatering.swift
//
//
//  Created by Julian Kahnert on 01.07.24.
//

#if canImport(WeatherKit)
import Foundation
import HAModels
import WeatherKit

public struct GardenWatering: Automatable {
    private static let weatherService = WeatherService.shared

    public var isActive = true
    public let name: String
    public let time: Time
    public let location: Location
    public let rainbirdZones: [ValveDevice]
    public var triggerEntityIds: Set<EntityId> {
        []
    }

    public init(_ name: String, time: Time, location: Location, rainbirdZones: [ValveDevice]) {
        self.name = name
        self.time = time
        self.location = location
        self.rainbirdZones = rainbirdZones
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        return time.isEqual(event)
    }

    public func execute(using hm: HomeManagable) async throws {
        // get weather data
        let now = Date()
        let tomorrow = now.tomorrow()
        let fourDaysAgo = now.fourDaysAgo()
        let response = try await Self.weatherService.weather(for: .init(latitude: location.latitude, longitude: location.longitude),
                                                             including: .daily(startDate: fourDaysAgo, endDate: tomorrow))
        log.info("Fetched data from [\(response.forecast.first?.date.formatted() ?? "")] until [\(response.forecast.last?.date.formatted() ?? "")]")
        for item in response.forecast {
            log.debug("precipitation: \(item.date.formatted()) - \(item.precipitationAmountByType.precipitation)")
        }

        let precipitations: [Measurement<UnitLength>]
        if #available(iOS 18.0, macCatalyst 18.0, macOS 15.0, *) {
            precipitations = response.forecast.map(\.precipitationAmountByType.precipitation)
        } else {
            precipitations = response.forecast.map(\.precipitationAmount)
        }
        let totalPrecipitationAmount = precipitations
            .map { $0.converted(to: .millimeters).value }
            .reduce(0, +)

        // only run watering when the precipitation amount is under a threshold (in mm)
        guard totalPrecipitationAmount < 7 else { return }

        for zone in rainbirdZones {
            await zone.turn(on: true, with: hm)
            try await Task.sleep(for: .seconds(1))
        }
    }
}
#endif

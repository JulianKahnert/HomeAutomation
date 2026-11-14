//
//  OutdoorTemperatureJobTests.swift
//  HomeAutomation
//

import Foundation
@testable import HAModels
@testable import Server
import Testing

struct OutdoorTemperatureJobTests {
    private let location = Location(latitude: 52.5, longitude: 13.4)
    private let response = Data(#"{"latitude":52.5,"hourly":{"time":["2026-11-14T11:00","2026-11-14T12:00"],"temperature_2m":[7.9,8.3],"cloud_cover":[100,null],"is_day":[1,1]}}"#.utf8)

    @Test func parsesOneRowPerHourWithAllVariables() throws {
        let fetched = Date(timeIntervalSince1970: 100)
        let hours = try OutdoorTemperatureJob.parseHours(response, location: location, fetchedAt: fetched)

        #expect(hours.count == 2)
        #expect(hours[1].hour == Date(timeIntervalSince1970: 1_794_657_600)) // 2026-11-14T12:00Z
        #expect(hours[1].temperatureInC == 8.3)
        #expect(hours[1].locationKey == "52.5,13.4")
        #expect(hours[1].fetchedAt == fetched)
        let first = try JSONSerialization.jsonObject(with: Data(hours[0].data.utf8)) as? [String: Double]
        let second = try JSONSerialization.jsonObject(with: Data(hours[1].data.utf8)) as? [String: Double]
        #expect(first == ["cloud_cover": 100, "is_day": 1, "temperature_2m": 7.9])
        #expect(second == ["is_day": 1, "temperature_2m": 8.3]) // null values are left out
    }

    @Test func rejectsResponseWithoutHourlyBlock() {
        #expect(throws: (any Error).self) { try OutdoorTemperatureJob.parseHours(Data("{}".utf8), location: location, fetchedAt: Date()) }
    }

    @Test func urlRequestsAllHourlyVariablesWithPastAndForecastDays() {
        let query = OutdoorTemperatureJob.url(for: location).absoluteString
        for variable in ["temperature_2m", "apparent_temperature", "relative_humidity_2m", "dew_point_2m", "precipitation", "cloud_cover", "wind_speed_10m", "wind_direction_10m", "shortwave_radiation", "direct_radiation", "diffuse_radiation", "direct_normal_irradiance", "sunshine_duration", "is_day"] {
            #expect(query.contains(variable))
        }
        #expect(query.contains("latitude=52.5&longitude=13.4"))
        #expect(query.contains("past_days=1"))
        #expect(query.contains("forecast_days=2"))
        #expect(query.contains("timezone=UTC"))
    }

    @Test func laterFetchOverwritesTheSameHour() async throws {
        let store = InMemoryWeather()
        var job = OutdoorTemperatureJob(location: location, weather: store)
        let first = response
        let second = Data(#"{"hourly":{"time":["2026-11-14T12:00","2026-11-14T13:00"],"temperature_2m":[9.0,9.5]}}"#.utf8)
        job.fetch = { _ in first }
        try await job.recordOnce(now: Date(timeIntervalSince1970: 100))
        job.fetch = { _ in second }
        try await job.recordOnce(now: Date(timeIntervalSince1970: 200))

        let rows = await store.rows.values.sorted { $0.hour < $1.hour }
        #expect(rows.map(\.temperatureInC) == [7.9, 9.0, 9.5])
        #expect(rows[1].fetchedAt == Date(timeIntervalSince1970: 200))
    }

    @Test func historyItemExposesHeatingFields() {
        let id = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: nil, characteristic: .valvePosition)
        let history = EntityHistoryItem(EntityStorageItem(entityId: id, targetTemperatureInC: 20.5, heatingMode: 1, valvePositionPercent: 35))
        #expect(history.targetTemperatureInC == 20.5)
        #expect(history.heatingMode == 1)
        #expect(history.valvePositionPercent == 35)
    }

    @Test func apiItemExposesHeatingFields() {
        let id = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: nil, characteristic: .valvePosition)
        let api = Components.Schemas.EntityHistoryItem(EntityStorageItem(entityId: id, targetTemperatureInC: 20.5, heatingMode: 3, valvePositionPercent: 35))
        #expect(api.targetTemperatureInC == 20.5)
        #expect(api.heatingMode == 3)
        #expect(api.valvePositionPercent == 35)
    }

    @Test func weatherHourMapsToApiSchema() {
        let value = WeatherHourValue(locationKey: "k", hour: Date(timeIntervalSince1970: 3600), temperatureInC: 4.5, fetchedAt: Date(timeIntervalSince1970: 7200), data: "{}")
        let api = Components.Schemas.WeatherHour(value)
        #expect(api.hour == value.hour)
        #expect(api.temperatureInC == 4.5)
        #expect(api.data == "{}")
    }

    @Test func eveValvePositionUUIDMatchesCaseInsensitively() {
        #expect(EveCharacteristic.isValvePosition("e863f12e-079e-48ff-8f27-9c2605a29f52"))
        #expect(!EveCharacteristic.isValvePosition("E863F12C-079E-48FF-8F27-9C2605A29F52"))
    }
}

private actor InMemoryWeather: WeatherHourStoring {
    private(set) var rows: [String: WeatherHourValue] = [:]
    func upsert(_ values: [WeatherHourValue]) async throws {
        for value in values { rows["\(value.locationKey)|\(value.hour.timeIntervalSince1970)"] = value }
    }
    func history(locationKey: String, startDate: Date?, endDate: Date?, cursor: Date?, limit: Int) async throws -> [WeatherHourValue] { [] }
}

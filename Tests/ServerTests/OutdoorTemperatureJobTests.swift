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

    @Test func storesOneTypedRowPerHour() async throws {
        let store = InMemoryHours()
        var job = OutdoorTemperatureJob(location: location, hours: store)
        let data = response
        job.fetch = { _ in data }

        try await job.recordOnce(now: Date(timeIntervalSince1970: 100))

        let rows = await store.rows
        #expect(rows.count == 2)
        #expect(rows[0].locationKey == "52.5,13.4")
        #expect(rows[0].hour == Date(timeIntervalSince1970: 1_794_654_000)) // 2026-11-14T11:00Z
        #expect(rows[1].hour.timeIntervalSince(rows[0].hour) == 3600)
        #expect(rows[0].temperature2mC == 7.9)
        #expect(rows[0].cloudCoverPercent == 100)
        #expect(rows[1].cloudCoverPercent == nil)
        #expect(rows[0].isDay == true)
        #expect(rows[0].windSpeed10mKmh == nil) // not in the response
        #expect(rows[0].fetchedAt == Date(timeIntervalSince1970: 100))
    }

    @Test func rejectsResponseWithoutHourlyBlock() async {
        let store = InMemoryHours()
        var job = OutdoorTemperatureJob(location: location, hours: store)
        job.fetch = { _ in Data(#"{"reason":"rate limit"}"#.utf8) }

        await #expect(throws: (any Error).self) { try await job.recordOnce() }
        #expect(await store.rows.isEmpty)
    }

    @Test func urlRequestsAllHourlyVariablesWithPastAndForecastDays() throws {
        let query = try OutdoorTemperatureJob.url(for: location).absoluteString
        for variable in ["temperature_2m", "apparent_temperature", "relative_humidity_2m", "dew_point_2m", "precipitation", "cloud_cover", "wind_speed_10m", "wind_direction_10m", "shortwave_radiation", "direct_radiation", "diffuse_radiation", "direct_normal_irradiance", "sunshine_duration", "is_day"] {
            #expect(query.contains(variable))
        }
        #expect(query.contains("latitude=52.5&longitude=13.4"))
        #expect(query.contains("past_days=1"))
        #expect(query.contains("forecast_days=2"))
        #expect(query.contains("timezone=UTC"))
    }

    @Test func historyItemExposesHeatingFields() {
        let id = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: nil, characteristic: .valvePosition)
        let history = EntityHistoryItem(EntityStorageItem(entityId: id, targetTemperatureInC: 20.5, heatingMode: .heat, valvePositionPercent: 35))
        #expect(history.targetTemperatureInC == 20.5)
        #expect(history.heatingMode == .heat)
        #expect(history.valvePositionPercent == 35)
    }

    @Test(arguments: HeatingMode.allCases)
    func heatingModeKeepsHAPRawValueAndApiName(_ mode: HeatingMode) {
        #expect(HeatingMode(name: mode.name) == mode)
        let id = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: nil, characteristic: .heatingMode)
        let api = Components.Schemas.EntityHistoryItem(EntityStorageItem(entityId: id, heatingMode: mode))
        #expect(api.heatingMode?.rawValue == mode.name)
        #expect(HeatingMode(rawValue: 4) == nil)
        #expect([HeatingMode.off, .heat, .cool, .auto].map(\.rawValue) == [0, 1, 2, 3])
    }

    @Test func apiItemExposesHeatingFields() {
        let id = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: nil, characteristic: .valvePosition)
        let api = Components.Schemas.EntityHistoryItem(EntityStorageItem(entityId: id, targetTemperatureInC: 20.5, heatingMode: .auto, valvePositionPercent: 35))
        #expect(api.targetTemperatureInC == 20.5)
        #expect(api.heatingMode?.rawValue == "auto")
        #expect(api.valvePositionPercent == 35)
    }

    @Test func eveValvePositionUUIDMatchesCaseInsensitively() {
        #expect(EveCharacteristic.isValvePosition("e863f12e-079e-48ff-8f27-9c2605a29f52"))
        #expect(!EveCharacteristic.isValvePosition("E863F12C-079E-48FF-8F27-9C2605A29F52"))
    }
}

private actor InMemoryHours: WeatherHourStoring {
    private(set) var rows: [WeatherHour] = []
    func upsert(_ hours: [WeatherHour]) async throws {
        rows.append(contentsOf: hours)
    }
}

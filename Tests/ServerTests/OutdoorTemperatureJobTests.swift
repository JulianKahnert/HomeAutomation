//
//  OutdoorTemperatureJobTests.swift
//  HomeAutomation
//

import Foundation
@testable import HAModels
@testable import Server
import Testing

struct OutdoorTemperatureJobTests {
    private let response = Data(#"{"latitude":52.5,"current":{"time":"2026-11-14T12:00","interval":900,"temperature_2m":8.3}}"#.utf8)

    @Test func parsesCurrentTemperature() throws {
        #expect(try OutdoorTemperatureJob.parseTemperature(response) == 8.3)
    }

    @Test func rejectsResponseWithoutTemperature() {
        #expect(throws: (any Error).self) { try OutdoorTemperatureJob.parseTemperature(Data("{}".utf8)) }
    }

    @Test func urlUsesLocation() {
        let url = OutdoorTemperatureJob.url(for: Location(latitude: 52.5, longitude: 13.4))
        #expect(url.absoluteString == "https://api.open-meteo.com/v1/forecast?latitude=52.5&longitude=13.4&current=temperature_2m&hourly=\(OutdoorTemperatureJob.hourlyVariables)&past_days=1&forecast_days=2&timezone=UTC")
    }

    @Test func recordOnceStoresOutdoorEntity() async throws {
        let repository = RecordingRepository()
        let snapshots = RecordingSnapshots()
        let data = response
        var job = OutdoorTemperatureJob(location: Location(latitude: 52.5, longitude: 13.4), storage: repository, snapshots: snapshots)
        job.fetch = { _ in data }

        let item = try await job.recordOnce(now: Date(timeIntervalSince1970: 100))

        #expect(item.entityId == OutdoorTemperatureJob.entityId)
        #expect(item.entityId.characteristicType == .outdoorTemperature)
        #expect(item.temperatureInC?.value == 8.3)
        #expect(await repository.items.count == 1)
        let stored = try #require(await snapshots.rows.first)
        #expect(stored.json == String(decoding: data, as: UTF8.self))
        #expect(stored.locationKey == "52.5,13.4")
        #expect(stored.fetchedAt == Date(timeIntervalSince1970: 100))
    }

    @Test func urlRequestsAllHourlyVariablesWithPastAndForecastDays() {
        let query = OutdoorTemperatureJob.url(for: Location(latitude: 1, longitude: 2)).absoluteString
        for variable in ["temperature_2m", "apparent_temperature", "relative_humidity_2m", "dew_point_2m", "precipitation", "cloud_cover", "wind_speed_10m", "wind_direction_10m", "shortwave_radiation", "direct_radiation", "diffuse_radiation", "direct_normal_irradiance", "sunshine_duration", "is_day"] {
            #expect(query.contains(variable))
        }
        #expect(query.contains("past_days=1"))
        #expect(query.contains("forecast_days=2"))
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

    @Test func eveValvePositionUUIDMatchesCaseInsensitively() {
        #expect(EveCharacteristic.isValvePosition("e863f12e-079e-48ff-8f27-9c2605a29f52"))
        #expect(!EveCharacteristic.isValvePosition("E863F12C-079E-48FF-8F27-9C2605A29F52"))
    }
}

private actor RecordingRepository: StorageRepository {
    private(set) var items: [EntityStorageItem] = []
    func add(_ item: EntityStorageItem) async throws { items.append(item) }
    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem? { nil }
    func getPrevious(_ entityId: EntityId) async throws -> EntityStorageItem? { nil }
    func deleteEntries(olderThan date: Date) async throws {}
    func getHistory(for entityId: EntityId, startDate: Date?, endDate: Date?, cursor: Date?, limit: Int) async throws -> [EntityStorageItem] { [] }
    func getAllEntityIds() async throws -> [EntityId] { [] }
}

private actor RecordingSnapshots: WeatherSnapshotStoring {
    private(set) var rows: [(locationKey: String, fetchedAt: Date, json: String)] = []
    func add(locationKey: String, fetchedAt: Date, json: String) async throws {
        rows.append((locationKey, fetchedAt, json))
    }
}

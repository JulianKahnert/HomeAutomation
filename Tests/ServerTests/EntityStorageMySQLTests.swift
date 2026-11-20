//
//  EntityStorageMySQLTests.swift
//  HomeAutomation
//
//  Runs only against a throwaway MySQL: set HA_TEST_MYSQL_PORT (host 127.0.0.1, database `t`, user `u`, password `p`), e.g.
//  docker run --rm -p 33307:3306 -e MYSQL_ROOT_PASSWORD=x -e MYSQL_DATABASE=t -e MYSQL_USER=u -e MYSQL_PASSWORD=p mysql:9
//  Never point it at a real database: it creates and fills the tables.

import Fluent
import FluentMySQLDriver
@testable import HAModels
@testable import Server
import SQLKit
import XCTVapor

final class EntityStorageMySQLTests: XCTestCase {
    private var app: Application!

    override func setUp() async throws {
        guard let port = ProcessInfo.processInfo.environment["HA_TEST_MYSQL_PORT"].flatMap(Int.init) else {
            throw XCTSkip("HA_TEST_MYSQL_PORT not set")
        }
        app = try await Application.make(.testing)
        var tls = TLSConfiguration.makeClientConfiguration()
        tls.certificateVerification = .none
        app.databases.use(.mysql(hostname: "127.0.0.1", port: port, username: "u", password: "p", database: "t", tlsConfiguration: tls), as: .mysql)
        app.migrations.add(CreateEntityStorageDbItem())
        app.migrations.add(AddSensorFields())
        app.migrations.add(CreateAutomationRun())
        app.migrations.add(AddLookupIndexes())
        app.migrations.add(AddHeatingControlFields())
        app.migrations.add(CreateWeatherHour())
        app.migrations.add(CreateEntityHourlyAggregate())
        app.migrations.add(AddTemperatureCalibration())
        app.migrations.add(CreateHeatingWrite())
        try await app.autoMigrate()
    }

    override func tearDown() async throws {
        if let app {
            try await app.autoRevert()
            try await app.asyncShutdown()
        }
    }

    func testHeatingFieldsRoundTripThroughTinyIntColumns() async throws {
        let repository = app.entityStorageDbRepository
        let id = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: "Thermostat", characteristic: .valvePosition)
        for (offset, values) in [(0, (.off, 0)), (1, (.auto, 100)), (2, (nil, nil))] as [(Int, (HeatingMode?, Int?))] {
            try await repository.add(EntityStorageItem(entityId: id,
                                                       timestamp: Date(timeIntervalSince1970: Double(1_000 + offset)),
                                                       heatingMode: values.0,
                                                       valvePositionPercent: values.1))
        }

        let items = try await repository.getHistory(for: id, startDate: nil, endDate: nil, cursor: nil, limit: 10)

        XCTAssertEqual(items.map(\.heatingMode), [nil, .auto, .off])
        XCTAssertEqual(items.map(\.valvePositionPercent), [nil, 100, 0])
    }

    func testTemperatureCalibrationRoundTrips() async throws {
        let repository = app.entityStorageDbRepository
        let id = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: "Thermostat", characteristic: .temperatureCalibration)
        for (offset, value) in [(0, -2.5), (1, 0.3), (2, nil)] as [(Int, Double?)] {
            try await repository.add(EntityStorageItem(entityId: id,
                                                       timestamp: Date(timeIntervalSince1970: Double(1_000 + offset)),
                                                       temperatureCalibrationInC: value))
        }

        let items = try await repository.getHistory(for: id, startDate: nil, endDate: nil, cursor: nil, limit: 10)

        XCTAssertEqual(items.map(\.temperatureCalibrationInC), [nil, 0.3, -2.5])
    }

    func testUnknownHeatingModeIsReadAsNil() async throws {
        let id = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: nil, characteristic: .heatingMode)
        try await EntityStorageDbItem(timestamp: Date(timeIntervalSince1970: 1_000),
                                      entityPlaceId: id.placeId,
                                      entityServiceName: id.name,
                                      entityCharacteristicType: id.characteristicType.rawValue,
                                      heatingMode: 9)
            .save(on: app.db)

        let item = try await app.entityStorageDbRepository.getCurrent(id)

        XCTAssertNotNil(item)
        XCTAssertNil(item?.heatingMode)
    }

    func testColumnsAreNarrowIntegers() async throws {
        let sql = try XCTUnwrap(app.db as? SQLDatabase)
        let rows = try await sql.raw("SELECT COLUMN_NAME, COLUMN_TYPE FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = 't' AND TABLE_NAME = 'entityItems' AND COLUMN_NAME IN ('heatingMode', 'valvePositionPercent')").all()
        let types = try Dictionary(uniqueKeysWithValues: rows.map { (try $0.decode(column: "COLUMN_NAME", as: String.self), try $0.decode(column: "COLUMN_TYPE", as: String.self)) })
        XCTAssertEqual(types["heatingMode"], "tinyint")
        XCTAssertEqual(types["valvePositionPercent"], "tinyint unsigned")
    }

    func testGetAllEntityIdsReturnsEachEntityOnceWithItsName() async throws {
        let repository = app.entityStorageDbRepository
        let temperature = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: "Thermostat", characteristic: .temperatureSensor)
        let valve = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: "Thermostat", characteristic: .valvePosition)
        let lamp = EntityId(placeId: "Hall", name: "Lamp", characteristicsName: nil, characteristic: .switcher)
        for (index, id) in [temperature, temperature, valve, lamp].enumerated() {
            try await repository.add(EntityStorageItem(entityId: id, timestamp: Date(timeIntervalSince1970: Double(index)), isDeviceOn: true))
        }

        let ids = try await repository.getAllEntityIds()

        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(Set(ids.map(\.description)), Set([temperature, valve, lamp].map(\.description)))
        XCTAssertEqual(ids.first { $0.characteristicType == .valvePosition }?.characteristicsName, "Thermostat")
        XCTAssertNil(ids.first { $0.characteristicType == .switcher }?.characteristicsName)
    }

    // MARK: - storage rules

    private let co2 = EntityId(placeId: "Kueche", name: "Air", characteristicsName: nil, characteristic: .carbonDioxideSensorId)
    private let hour = Date(timeIntervalSince1970: 1_699_999_200)

    private func insertRaw(_ id: EntityId, minutes: Double, co2: Int? = nil, lux: Double? = nil, isOn: Bool? = nil) async throws {
        try await EntityStorageDbItem(timestamp: hour.addingTimeInterval(minutes * 60),
                                      entityPlaceId: id.placeId,
                                      entityServiceName: id.name,
                                      entityCharacteristicType: id.characteristicType.rawValue,
                                      illuminanceInLux: lux,
                                      isDeviceOn: isOn,
                                      carbonDioxideSensorId: co2)
            .save(on: app.db)
    }

    func testCO2WriteSkipsValuesInsideTheDeadBand() async throws {
        let repository = app.entityStorageDbRepository
        for (minutes, ppm) in [(0.0, 800), (1, 810), (2, 776), (3, 830), (4, 0), (5, 10), (20, 10)] {
            try await repository.add(EntityStorageItem(entityId: co2, timestamp: hour.addingTimeInterval(minutes * 60), carbonDioxideSensorId: ppm))
        }

        let items = try await repository.getHistory(for: co2, startDate: nil, endDate: nil, cursor: nil, limit: 10)

        // 810 and 776 are within 25 ppm of 800; 10 within 25 of 0; the last 10 comes after 15 minutes.
        XCTAssertEqual(items.map(\.carbonDioxideSensorId), [10, 0, 830, 800])
    }

    func testRollupAggregatesPerHourWithoutZeroPPMAndDeletesRawRows() async throws {
        let repository = app.entityStorageDbRepository
        let lamp = EntityId(placeId: "Kueche", name: "Lamp", characteristicsName: nil, characteristic: .switcher)
        let lux = EntityId(placeId: "Kueche", name: "Lux", characteristicsName: nil, characteristic: .lightSensor)
        for (minutes, ppm) in [(5.0, 0), (10, 400), (20, 600), (50, 500), (70, 700), (125, 900)] {
            try await insertRaw(co2, minutes: minutes, co2: ppm)
        }
        try await insertRaw(lamp, minutes: 10, isOn: true)
        try await insertRaw(lux, minutes: 10, lux: 0)

        try await repository.rollUpHourly(type: .carbonDioxideSensorId,
                                          column: .carbonDioxideSensorId,
                                          validRange: StoragePolicy.policy(for: .carbonDioxideSensorId).validRange,
                                          olderThan: hour.addingTimeInterval(2 * 3600))

        let aggregates = try await repository.hourlyAggregates(of: co2)
        XCTAssertEqual(aggregates, [
            EntityHourlyAggregate(entityId: co2, hourStart: hour, minValue: 400, meanValue: 500, maxValue: 600, lastValue: 500, valueCount: 3),
            EntityHourlyAggregate(entityId: co2, hourStart: hour.addingTimeInterval(3600), minValue: 700, meanValue: 700, maxValue: 700, lastValue: 700, valueCount: 1)
        ])
        let remaining = try await repository.getHistory(for: co2, startDate: nil, endDate: nil, cursor: nil, limit: 10)
        XCTAssertEqual(remaining.map(\.carbonDioxideSensorId), [900])
        let lampRows = try await repository.getHistory(for: lamp, startDate: nil, endDate: nil, cursor: nil, limit: 10)
        XCTAssertEqual(lampRows.count, 1)
        let luxRows = try await repository.getHistory(for: lux, startDate: nil, endDate: nil, cursor: nil, limit: 10)
        XCTAssertEqual(luxRows.count, 1)
    }

    func testRollupMergesALateRowIntoAnExistingHour() async throws {
        let repository = app.entityStorageDbRepository
        let cutoff = hour.addingTimeInterval(3600)
        try await insertRaw(co2, minutes: 10, co2: 400)
        try await repository.rollUpHourly(type: .carbonDioxideSensorId, column: .carbonDioxideSensorId, validRange: 1...100_000, olderThan: cutoff)
        try await insertRaw(co2, minutes: 30, co2: 800)
        try await repository.rollUpHourly(type: .carbonDioxideSensorId, column: .carbonDioxideSensorId, validRange: 1...100_000, olderThan: cutoff)

        let aggregates = try await repository.hourlyAggregates(of: co2)
        XCTAssertEqual(aggregates, [EntityHourlyAggregate(entityId: co2, hourStart: hour, minValue: 400, meanValue: 600, maxValue: 800, lastValue: 800, valueCount: 2)])
    }

    func testDeleteEntriesOfTypeKeepsOtherTypes() async throws {
        let repository = app.entityStorageDbRepository
        let lamp = EntityId(placeId: "Kueche", name: "Lamp", characteristicsName: nil, characteristic: .switcher)
        try await insertRaw(co2, minutes: 0, co2: 500)
        try await insertRaw(co2, minutes: 90, co2: 600)
        try await insertRaw(lamp, minutes: 0, isOn: true)

        try await repository.deleteEntries(ofType: .carbonDioxideSensorId, olderThan: hour.addingTimeInterval(3600))

        let co2Rows = try await repository.getHistory(for: co2, startDate: nil, endDate: nil, cursor: nil, limit: 10)
        XCTAssertEqual(co2Rows.map(\.carbonDioxideSensorId), [600])
        let lampRows = try await repository.getHistory(for: lamp, startDate: nil, endDate: nil, cursor: nil, limit: 10)
        XCTAssertEqual(lampRows.count, 1)
    }

    func testEntitiesWithRowCountFindsOnlyNoisyEntitiesInTheWindow() async throws {
        let repository = app.entityStorageDbRepository
        let lamp = EntityId(placeId: "Kueche", name: "Lamp", characteristicsName: nil, characteristic: .switcher)
        for minute in 0..<6 {
            try await insertRaw(co2, minutes: Double(minute), co2: 500 + minute)
        }
        try await insertRaw(co2, minutes: -10, co2: 400)
        try await insertRaw(lamp, minutes: 1, isOn: true)

        let noisy = try await repository.entitiesWithRowCount(above: 5, since: hour)

        XCTAssertEqual(noisy, [EntityRowCount(placeId: "Kueche", serviceName: "Air", characteristicType: "carbonDioxideSensorId", rows: 6)])
    }

    func testTypeTimestampIndexServesTheRollupSelection() async throws {
        let sql = try XCTUnwrap(app.db as? SQLDatabase)
        let rows = try await sql.raw("SELECT COLUMN_NAME FROM information_schema.statistics WHERE TABLE_SCHEMA = 't' AND TABLE_NAME = 'entityItems' AND INDEX_NAME = 'idx_entityItems_type_timestamp' ORDER BY SEQ_IN_INDEX").all()
        XCTAssertEqual(try rows.map { try $0.decode(column: "COLUMN_NAME", as: String.self) }, ["entityCharacteristicType", "timestamp"])
    }

    // MARK: - weather

    func testWeatherUpsertOverwritesAnHourWithTheNewerFetch() async throws {
        let app = try XCTUnwrap(app)
        let repository = WeatherHourDbRepository(database: { app.db })
        let hour = Date(timeIntervalSince1970: 1_794_654_000)
        let forecast = WeatherHour(locationKey: "52.5,13.4",
                                   hour: hour,
                                   fetchedAt: hour.addingTimeInterval(-86_400),
                                   temperature2mC: 7.5,
                                   relativeHumidity2mPercent: 80,
                                   cloudCoverPercent: 100,
                                   windDirection10mDeg: 270,
                                   shortwaveRadiationWm2: 12,
                                   isDay: true)
        var observed = forecast
        observed.fetchedAt = hour.addingTimeInterval(3600)
        observed.temperature2mC = 8.25
        observed.cloudCoverPercent = nil
        var next = forecast
        next.hour = hour.addingTimeInterval(3600)

        try await repository.upsert([forecast])
        try await repository.upsert([observed, next])

        let rows = try await repository.hours(locationKey: "52.5,13.4")
        XCTAssertEqual(rows, [observed, next])
    }

    func testLatestOutdoorTemperatureIsTheCurrentHoursReadingNotAForecast() async throws {
        let app = try XCTUnwrap(app)
        let repository = WeatherHourDbRepository(database: { app.db })
        let hour = Date(timeIntervalSince1970: 1_794_654_000)
        func reading(_ location: String, hoursFromNow offset: Double, _ temperature: Double?) -> WeatherHour {
            WeatherHour(locationKey: location,
                        hour: hour.addingTimeInterval(offset * 3600),
                        fetchedAt: hour,
                        temperature2mC: temperature)
        }
        let now = hour.addingTimeInterval(20 * 60)

        let before = try await repository.latestTemperature(locationKey: "52.5,13.4", at: now)
        XCTAssertNil(before)

        try await repository.upsert([
            reading("52.5,13.4", hoursFromNow: -2, 5),
            reading("52.5,13.4", hoursFromNow: -1, 6.5),
            reading("52.5,13.4", hoursFromNow: 0, nil),
            reading("52.5,13.4", hoursFromNow: 1, 9),
            reading("48.1,11.6", hoursFromNow: 0, 12)
        ])

        let latest = try await repository.latestTemperature(locationKey: "52.5,13.4", at: now)
        XCTAssertEqual(latest, 6.5)
    }

    func testHeatingWritesAreQueryableByRoomAndTimeRange() async throws {
        let repository = app.heatingWriteRepository
        let kitchen = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: nil, characteristic: .targetTemperature)
        let bath = EntityId(placeId: "Bath", name: "Thermo", characteristicsName: nil, characteristic: .targetTemperature)
        func write(_ id: EntityId, at seconds: Double, reason: HeatingWriteReason, plan: Double?) -> HeatingWrite {
            HeatingWrite(timestamp: Date(timeIntervalSince1970: seconds), entityId: id, reason: reason, actionName: "setTargetTemperature", targetTemperatureInC: 21, planTargetInC: plan)
        }
        try await repository.add(write(kitchen, at: 3_000, reason: .system, plan: 21))
        try await repository.add(write(kitchen, at: 1_000, reason: .plan, plan: 21))
        try await repository.add(write(kitchen, at: 2_000, reason: .window, plan: nil))
        try await repository.add(write(bath, at: 2_000, reason: .plan, plan: 22))

        let all = try await repository.writes(placeId: "Kitchen", startDate: nil, endDate: nil)
        XCTAssertEqual(all.map(\.reason), [.plan, .window, .system])

        let ranged = try await repository.writes(placeId: "Kitchen", startDate: Date(timeIntervalSince1970: 1_500), endDate: Date(timeIntervalSince1970: 3_000))
        XCTAssertEqual(ranged.map(\.reason), [.window])
        XCTAssertNil(ranged.first?.planTargetInC)
    }
}

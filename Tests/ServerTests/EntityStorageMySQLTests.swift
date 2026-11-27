//
//  EntityStorageMySQLTests.swift
//  HomeAutomation
//
//  Runs only against a throwaway MySQL: set HA_TEST_MYSQL_PORT (host 127.0.0.1, database `t`, user `u`, password `p`), e.g.
//  docker run --rm -p 33307:3306 -e MYSQL_ROOT_PASSWORD=x -e MYSQL_DATABASE=t -e MYSQL_USER=u -e MYSQL_PASSWORD=p mysql:9
//  Never point it at a real database: it creates and fills the tables.

import Fluent
import FluentMySQLDriver
import HAApplicationLayer
@testable import HAModels
@testable import Server
import SQLKit
import StarActorSystem
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
        for migration in ServerMigrations.all { app.migrations.add(migration) }
        try await app.autoMigrate()
    }

    override func tearDown() async throws {
        if let app {
            try await app.autoRevert()
            try await app.asyncShutdown()
        }
    }

    /// The history route answers from the database for history older than the 3 hours the HomeManager keeps in memory.
    func testHistoryRouteReadsTheWholeHistoryFromTheDatabase() async throws {
        app.environment.arguments = ["serve"]
        app.authToken = "history-test-token"
        app.authDisabled = false
        app.homeAutomationConfigService = HomeAutomationConfigService(location: Location(latitude: 52.52, longitude: 13.405), persist: { _ in })
        app.automationService = try await makeAutomationService(automations: [])
        app.starActorSystem = StarActorSystem(name: "history-tests")
        let repository = app.entityStorageDbRepository
        let homeManager = await HomeManager(getAdapter: { nil },
                                            storageRepo: repository,
                                            notificationSender: SilentSender(),
                                            location: Location(latitude: 52.52, longitude: 13.405))
        app.homeManager = homeManager
        try routes(app)
        let id = EntityId(placeId: "Kitchen", name: "Sensor", characteristicsName: nil, characteristic: .temperatureSensor)
        let now = Date()
        for (hoursAgo, value) in [(30.0, 17.0), (10.0, 18.0), (0.5, 19.0)] {
            let item = EntityStorageItem(entityId: id,
                                         timestamp: now.addingTimeInterval(-hoursAgo * 3600),
                                         temperatureInC: Measurement(value: value, unit: .celsius))
            try await repository.add(item)
        }
        await homeManager.loadCurrentStates(timeout: .seconds(5))

        let path = "/entities/history?placeId=Kitchen&name=Sensor&characteristicType=\(CharacteristicsType.temperatureSensor.rawValue)"
        let authorize: (inout XCTHTTPRequest) -> Void = { $0.headers.add(name: .authorization, value: "Bearer history-test-token") }
        try await app.test(.GET, path, beforeRequest: authorize, afterResponse: { res async throws in
            XCTAssertEqual(res.status, .ok)
            let body = try XCTUnwrap(String(data: Data(res.body.readableBytesView), encoding: .utf8))
            XCTAssertEqual(body.components(separatedBy: "\"timestamp\"").count - 1, 3)
        })
    }

    func testHeatingFieldsRoundTrip() async throws {
        let repository = app.entityStorageDbRepository
        let mode = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: "Thermostat", characteristic: .heatingMode)
        let valve = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: "Thermostat", characteristic: .valvePosition)
        let calibration = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: "Thermostat", characteristic: .temperatureCalibration)
        for (offset, values) in [(0, (HeatingMode.off, 0, -2.5)), (1, (.auto, 100, 0.3))] {
            let timestamp = Date(timeIntervalSince1970: Double(1_000 + offset))
            try await repository.add(EntityStorageItem(entityId: mode, timestamp: timestamp, heatingMode: values.0))
            try await repository.add(EntityStorageItem(entityId: valve, timestamp: timestamp, valvePositionPercent: values.1))
            try await repository.add(EntityStorageItem(entityId: calibration, timestamp: timestamp, temperatureCalibrationInC: values.2))
        }

        let modes = try await repository.getHistory(for: mode, startDate: nil, endDate: nil, cursor: nil, limit: 10)
        let valves = try await repository.getHistory(for: valve, startDate: nil, endDate: nil, cursor: nil, limit: 10)
        let calibrations = try await repository.getHistory(for: calibration, startDate: nil, endDate: nil, cursor: nil, limit: 10)

        XCTAssertEqual(modes.map(\.heatingMode), [.auto, .off])
        XCTAssertEqual(valves.map(\.valvePositionPercent), [100, 0])
        XCTAssertEqual(calibrations.map(\.temperatureCalibrationInC), [0.3, -2.5])
    }

    func testUnknownHeatingModeIsReadAsNil() async throws {
        let id = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: nil, characteristic: .heatingMode)
        try await insertChange(id, at: 1_000, .number(9))

        let item = try await app.entityStorageDbRepository.getCurrent(id)

        XCTAssertNotNil(item)
        XCTAssertNil(item?.heatingMode)
    }

    func testEveryValueKindIsStoredAndReadBackUnchanged() async throws {
        let repository = app.entityStorageDbRepository
        for (index, sample) in EntityStorageMappingTests.samples.enumerated() {
            let id = EntityId(placeId: "Room", name: "Device\(index)", characteristicsName: "Name", characteristic: sample.0)
            let item = try XCTUnwrap(EntityStorageItem(entityId: id, timestamp: Date(timeIntervalSince1970: 1_000), value: sample.1, origin: .job("valves")))
            try await repository.add(item)

            let restored = try await repository.getCurrent(id)

            XCTAssertEqual(restored, item, "\(sample.0)")
        }
    }

    func testOldTableIsGone() async throws {
        let repository = app.entityStorageDbRepository
        let id = EntityId(placeId: "Hall", name: "Lamp", characteristicsName: nil, characteristic: .switcher)
        try await repository.add(EntityStorageItem(entityId: id, timestamp: Date(timeIntervalSince1970: 1_000), isDeviceOn: true))

        let sql = try XCTUnwrap(app.db as? SQLDatabase)
        let old = try await sql.raw("SELECT TABLE_NAME FROM information_schema.tables WHERE TABLE_SCHEMA = 't' AND TABLE_NAME = 'entityItems'").all().count
        let entities = try await EntityDbItem.query(on: app.db).count()
        let changes = try await EntityChangeDbItem.query(on: app.db).count()

        XCTAssertEqual([old, entities, changes], [0, 1, 1])
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

    func testGetAllCurrentReturnsTheNewestStateOfEveryEntity() async throws {
        let repository = app.entityStorageDbRepository
        let contact = EntityId(placeId: "Kitchen", name: "Window", characteristicsName: "Contact", characteristic: .contactSensor)
        let lamp = EntityId(placeId: "Hall", name: "Lamp", characteristicsName: nil, characteristic: .switcher)
        try await repository.add(EntityStorageItem(entityId: contact, timestamp: Date(timeIntervalSince1970: 1_000), isContactOpen: false))
        try await repository.add(EntityStorageItem(entityId: contact, timestamp: Date(timeIntervalSince1970: 3_000), isContactOpen: true))
        try await repository.add(EntityStorageItem(entityId: lamp, timestamp: Date(timeIntervalSince1970: 2_000), isDeviceOn: true))
        try await repository.add(EntityStorageItem(entityId: lamp, timestamp: Date(timeIntervalSince1970: 1_500), isDeviceOn: false))
        let gone = EntityDbItem(placeId: "Hall", serviceName: "Gone", characteristicType: "noLongerKnown", characteristicsName: nil)
        try await gone.save(on: app.db)
        try await EntityChangeDbItem(entityId: gone.requireID(), timestamp: Date(timeIntervalSince1970: 4_000), value: .bool(true), origin: "homekit").save(on: app.db)

        let items = try await repository.getAllCurrent().sorted { $0.entityId.placeId < $1.entityId.placeId }

        XCTAssertEqual(items.map(\.entityId.description), [lamp.description, contact.description])
        XCTAssertEqual(items.map(\.timestamp), [Date(timeIntervalSince1970: 2_000), Date(timeIntervalSince1970: 3_000)])
        XCTAssertEqual(items.first?.isDeviceOn, true)
        XCTAssertEqual(items.last?.isContactOpen, true)
        XCTAssertEqual(items.last?.entityId.characteristicsName, "Contact")
    }

    func testGetAllCurrentPicksTheRowOfGetCurrentForEqualTimestamps() async throws {
        let repository = app.entityStorageDbRepository
        let lamp = EntityId(placeId: "Hall", name: "Lamp", characteristicsName: nil, characteristic: .switcher)
        for (id, isDeviceOn) in [("00000000-0000-0000-0000-000000000002", true), ("00000000-0000-0000-0000-000000000001", false)] {
            try await insertChange(lamp, at: 1_000, .bool(isDeviceOn), changeId: UUID(uuidString: id))
        }

        let all = try await repository.getAllCurrent()
        let current = try await repository.getCurrent(lamp)

        XCTAssertEqual(all.map(\.isDeviceOn), [true])
        XCTAssertEqual(current?.isDeviceOn, true)
    }

    // MARK: - storage rules

    private let co2 = EntityId(placeId: "Kueche", name: "Air", characteristicsName: nil, characteristic: .carbonDioxideSensorId)
    private let hour = Date(timeIntervalSince1970: 1_699_999_200)

    private func insertRaw(_ id: EntityId, minutes: Double, co2: Int? = nil, lux: Double? = nil, isOn: Bool? = nil) async throws {
        let value: Value = co2.map { .number(Double($0)) } ?? lux.map { .number($0) } ?? .bool(isOn ?? false)
        try await insertChange(id, at: hour.timeIntervalSince1970 + minutes * 60, value)
    }

    /// Writes a change row directly, past the repository's dead band.
    private func insertChange(_ id: EntityId, at seconds: Double, _ value: Value, changeId: UUID? = nil) async throws {
        let entity: EntityDbItem
        let entityQuery = EntityDbItem.query(on: app.db)
            .filter(\.$placeId == id.placeId).filter(\.$serviceName == id.name)
            .filter(\.$characteristicType == id.characteristicType.rawValue)
        if let existing = try await entityQuery.first() {
            entity = existing
        } else {
            entity = EntityDbItem(placeId: id.placeId, serviceName: id.name, characteristicType: id.characteristicType.rawValue, characteristicsName: id.characteristicsName)
            try await entity.save(on: app.db)
        }
        let change = try EntityChangeDbItem(entityId: entity.requireID(), timestamp: Date(timeIntervalSince1970: seconds), value: value, shape: ValueDescriptor.descriptor(for: id.characteristicType).shape, origin: "homekit")
        change.id = changeId
        try await change.save(on: app.db)
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
                                          validRange: ValueDescriptor.descriptor(for: .carbonDioxideSensorId).storage.validRange,
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
        try await repository.rollUpHourly(type: .carbonDioxideSensorId, validRange: 1...100_000, olderThan: cutoff)
        try await insertRaw(co2, minutes: 30, co2: 800)
        try await repository.rollUpHourly(type: .carbonDioxideSensorId, validRange: 1...100_000, olderThan: cutoff)

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

    func testChangeIndexServesTheEntityLookup() async throws {
        let sql = try XCTUnwrap(app.db as? SQLDatabase)
        let rows = try await sql.raw("SELECT COLUMN_NAME FROM information_schema.statistics WHERE TABLE_SCHEMA = 't' AND TABLE_NAME = 'entityChanges' AND INDEX_NAME = 'idx_entityChanges_entity_timestamp' ORDER BY SEQ_IN_INDEX").all()
        XCTAssertEqual(try rows.map { try $0.decode(column: "COLUMN_NAME", as: String.self) }, ["entityId", "timestamp"])
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

    func testHeatingCommandsAreQueryableByRoomAndTimeRange() async throws {
        let repository = app.journalRepository
        let kitchen = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: nil, characteristic: .targetTemperature)
        let bath = EntityId(placeId: "Bath", name: "Thermo", characteristicsName: nil, characteristic: .targetTemperature)
        func command(_ id: EntityId, at seconds: Double, reason: HeatingWriteReason?, plan: Double?) -> ActionLogItem {
            ActionLogItem(timestamp: Date(timeIntervalSince1970: seconds), action: .setTargetTemperature(id, celsius: 21), reason: reason, planTargetInC: plan)
        }
        try await repository.addCommand(command(kitchen, at: 3_000, reason: .system, plan: 21))
        try await repository.addCommand(command(kitchen, at: 1_000, reason: .plan, plan: 21))
        try await repository.addCommand(command(kitchen, at: 2_000, reason: .window, plan: nil))
        try await repository.addCommand(command(kitchen, at: 2_500, reason: nil, plan: nil))
        try await repository.addCommand(command(bath, at: 2_000, reason: .plan, plan: 22))

        let all = try await repository.heatingCommands(placeId: "Kitchen", startDate: nil, endDate: nil)
        XCTAssertEqual(all.map(\.reason), [.plan, .window, .system])
        XCTAssertEqual(all.first?.value, 21)
        let lastPerRadiator = try await repository.lastHeatingCommands()
        XCTAssertEqual(Set(lastPerRadiator.map(\.entityId.placeId)), ["Kitchen", "Bath"])

        let ranged = try await repository.heatingCommands(placeId: "Kitchen", startDate: Date(timeIntervalSince1970: 1_500), endDate: Date(timeIntervalSince1970: 3_000))
        XCTAssertEqual(ranged.map(\.reason), [.window])
        XCTAssertNil(ranged.first?.planTargetInC)
    }

    func testJournalCleanupKeepsHeatingCommandsForGood() async throws {
        let journal = app.journalRepository
        let kitchen = EntityId(placeId: "Kitchen", name: "Radiator", characteristicsName: nil, characteristic: .targetTemperature)
        let old = Date(timeIntervalSince1970: 1_000)
        try await journal.addCommand(ActionLogItem(timestamp: old, action: .setTargetTemperature(kitchen, celsius: 21), reason: .plan))
        try await journal.addCommand(ActionLogItem(timestamp: old, action: .setTargetTemperature(kitchen, celsius: 18)))
        try await journal.addPush(JournalPush(timestamp: old, runId: nil, title: "t", message: "m", pushId: "p"))

        try await journal.deleteEntries(olderThan: Date())

        let commands = try await journal.commands(limit: nil, runId: nil)
        XCTAssertEqual(commands.map(\.reason), [.plan])
        let pushes = try await journal.pushes(runId: nil)
        XCTAssertTrue(pushes.isEmpty)
    }
}

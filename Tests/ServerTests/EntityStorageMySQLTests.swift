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

            // the current state also carries the time of its last report, which is the change's own time here
            var expected = item
            expected.lastReport = item.timestamp
            XCTAssertEqual(restored, expected, "\(sample.0)")
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
        let items = [
            EntityStorageItem(entityId: temperature, timestamp: Date(timeIntervalSince1970: 0), temperatureInC: Measurement(value: 20, unit: .celsius)),
            EntityStorageItem(entityId: temperature, timestamp: Date(timeIntervalSince1970: 1), temperatureInC: Measurement(value: 22, unit: .celsius)),
            EntityStorageItem(entityId: valve, timestamp: Date(timeIntervalSince1970: 2), valvePositionPercent: 40),
            EntityStorageItem(entityId: lamp, timestamp: Date(timeIntervalSince1970: 3), isDeviceOn: true)
        ]
        for item in items {
            try await repository.add(item)
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
        // A directory entry without any change is no state; one of an unknown type is skipped.
        try await EntityDbItem(placeId: "Hall", serviceName: "Empty", characteristicType: CharacteristicsType.switcher.rawValue, characteristicsName: nil).save(on: app.db)
        let gone = EntityDbItem(placeId: "Hall", serviceName: "Gone", characteristicType: "noLongerKnown", characteristicsName: nil)
        try await gone.save(on: app.db)
        try await EntityChangeDbItem(entityId: gone.requireID(), timestamp: Date(timeIntervalSince1970: 4_000), value: .bool(true), origin: "homekit").save(on: app.db)

        let items = try await repository.getAllCurrent().sorted { $0.entityId.placeId < $1.entityId.placeId }

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.entityId.description), [lamp.description, contact.description])
        XCTAssertEqual(items.map(\.timestamp), [Date(timeIntervalSince1970: 2_000), Date(timeIntervalSince1970: 3_000)])
        XCTAssertEqual(items.first?.isDeviceOn, true)
        XCTAssertEqual(items.last?.isContactOpen, true)
        XCTAssertEqual(items.last?.entityId.characteristicsName, "Contact")
    }

    func testGetAllCurrentPicksTheRowOfGetCurrentForEqualTimestamps() async throws {
        let repository = app.entityStorageDbRepository
        let lamp = EntityId(placeId: "Hall", name: "Lamp", characteristicsName: nil, characteristic: .switcher)
        // Equal timestamps: the row written last (the higher id) is the current one.
        for isDeviceOn in [false, true] {
            try await insertChange(lamp, at: 1_000, .bool(isDeviceOn))
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
    private func insertChange(_ id: EntityId, at seconds: Double, _ value: Value) async throws {
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

    /// A change stores the time of its report with it; a report that changed nothing writes only that time, and an
    /// older time never replaces a newer one. Only the current state carries it, the history does not.
    func testLastReportIsStoredWithAChangeAndByAnUnchangedReport() async throws {
        let repository = app.entityStorageDbRepository
        let lamp = EntityId(placeId: "Kueche", name: "Lamp", characteristicsName: nil, characteristic: .switcher)
        let reported = hour.addingTimeInterval(120)
        try await repository.add(EntityStorageItem(entityId: lamp, timestamp: hour, isDeviceOn: true))
        var current = try await repository.getCurrent(lamp)
        XCTAssertEqual(current?.lastReport, hour, "a stored change shows as a report through its own timestamp")
        // the HomeManager writes the time of a change's report through the same throttled call as an unchanged report
        try await repository.recordLastReport(of: lamp, at: reported)
        current = try await repository.getCurrent(lamp)
        XCTAssertEqual(current?.lastReport, reported)

        try await repository.recordLastReport(of: lamp, at: reported.addingTimeInterval(400))
        try await repository.recordLastReport(of: lamp, at: reported.addingTimeInterval(100))
        current = try await repository.getCurrent(lamp)
        XCTAssertEqual(current?.lastReport, reported.addingTimeInterval(400))
        let all = try await repository.getAllCurrent()
        XCTAssertEqual(all.first { $0.entityId == lamp }?.lastReport, reported.addingTimeInterval(400))

        let history = try await repository.getHistory(for: lamp, startDate: nil, endDate: nil, cursor: nil, limit: 10)
        XCTAssertEqual(history.map(\.lastReport), [nil])
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

    // MARK: - tuning (M1-M18 of the MySQL review)

    /// `getHistory` orders equal timestamps by id, newest write first.
    func testHistoryOrdersEqualTimestampsByTheRowWrittenLast() async throws {
        let repository = app.entityStorageDbRepository
        let lamp = EntityId(placeId: "Hall", name: "Lamp", characteristicsName: nil, characteristic: .switcher)
        for isDeviceOn in [true, false, true] {
            try await insertChange(lamp, at: 1_000, .bool(isDeviceOn))
        }
        try await insertChange(lamp, at: 2_000, .bool(false))

        let history = try await repository.getHistory(for: lamp, startDate: nil, endDate: nil, cursor: nil, limit: 10)

        XCTAssertEqual(history.map(\.isDeviceOn), [false, true, false, true])
    }

    /// The rollup works one entity and one day at a time: rows over several days and two entities all end up rolled up.
    func testRollupAcrossSeveralDaysAndEntitiesKeepsTheNewerRows() async throws {
        let repository = app.entityStorageDbRepository
        let second = EntityId(placeId: "Bad", name: "Air", characteristicsName: nil, characteristic: .carbonDioxideSensorId)
        for day in 0..<3 {
            for id in [co2, second] {
                try await insertRaw(id, minutes: Double(day * 1_440 + 10), co2: 400 + day)
                try await insertRaw(id, minutes: Double(day * 1_440 + 20), co2: 500 + day)
            }
        }
        let cutoff = hour.addingTimeInterval(2 * 86_400)  // keeps the third day's rows

        try await repository.rollUpHourly(type: .carbonDioxideSensorId, validRange: 1...100_000, olderThan: cutoff)

        for id in [co2, second] {
            let aggregates = try await repository.hourlyAggregates(of: id)
            XCTAssertEqual(aggregates.map(\.hourStart), [hour, hour.addingTimeInterval(86_400)])
            XCTAssertEqual(aggregates.map(\.valueCount), [2, 2])
            XCTAssertEqual(aggregates.map(\.lastValue), [500, 501])
            let remaining = try await repository.getHistory(for: id, startDate: nil, endDate: nil, cursor: nil, limit: 10)
            XCTAssertEqual(remaining.map(\.carbonDioxideSensorId), [502, 402])
        }
    }

    /// More rows than one delete batch: every old row of the type goes, a newer one and other types stay.
    func testDeleteEntriesOfTypeDeletesMoreThanOneBatch() async throws {
        let repository = app.entityStorageDbRepository
        let lamp = EntityId(placeId: "Kueche", name: "Lamp", characteristicsName: nil, characteristic: .switcher)
        try await insertRaw(lamp, minutes: 0, isOn: true)
        try await insertRaw(co2, minutes: 0, co2: 500)  // creates the directory entry
        let entities = try await EntityDbItem.query(on: app.db).filter(\.$serviceName == "Air").all()
        let entityKey = try XCTUnwrap(entities.first).requireID()
        let rows = (0...EntityStorageDbRepository.deleteBatchSize).map { index in
            EntityChangeDbItem(entityId: entityKey, timestamp: hour.addingTimeInterval(-Double(index + 1)), value: .number(500), origin: "homekit")
        }
        for chunk in stride(from: 0, to: rows.count, by: 2_000) {
            try await rows[chunk..<min(chunk + 2_000, rows.count)].create(on: app.db)
        }
        try await insertRaw(co2, minutes: 90, co2: 600)

        try await repository.deleteEntries(ofType: .carbonDioxideSensorId, olderThan: hour.addingTimeInterval(3_600))

        let co2Rows = try await repository.getHistory(for: co2, startDate: nil, endDate: nil, cursor: nil, limit: 10)
        XCTAssertEqual(co2Rows.map(\.carbonDioxideSensorId), [600])
        let lampRows = try await repository.getHistory(for: lamp, startDate: nil, endDate: nil, cursor: nil, limit: 10)
        XCTAssertEqual(lampRows.count, 1)
    }

    /// Names that differ only in case or accent are different entities (binary collation).
    func testNamesDifferingInCaseOrAccentAreDifferentEntities() async throws {
        let repository = app.entityStorageDbRepository
        let names = ["Bad", "bad", "Küche", "Kuche"]
        for (index, name) in names.enumerated() {
            let id = EntityId(placeId: name, name: "Lamp", characteristicsName: nil, characteristic: .switcher)
            try await repository.add(EntityStorageItem(entityId: id, timestamp: Date(timeIntervalSince1970: Double(index)), isDeviceOn: true))
        }

        let ids = try await repository.getAllEntityIds()
        XCTAssertEqual(Set(ids.map(\.placeId)), Set(names))
        for name in names {
            let id = EntityId(placeId: name, name: "Lamp", characteristicsName: nil, characteristic: .switcher)
            let history = try await repository.getHistory(for: id, startDate: nil, endDate: nil, cursor: nil, limit: 10)
            XCTAssertEqual(history.count, 1, name)
        }
    }

    /// A change read back from `DATETIME(6)` is the one held in memory: the full history lists it once.
    func testFullHistoryListsAChangeOnceAfterItWasStored() async throws {
        let repository = app.entityStorageDbRepository
        let homeManager = await HomeManager(getAdapter: { nil },
                                            storageRepo: repository,
                                            notificationSender: SilentSender(),
                                            location: Location(latitude: 52.52, longitude: 13.405))
        let id = EntityId(placeId: "Kitchen", name: "Sensor", characteristicsName: nil, characteristic: .temperatureSensor)
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000.123_456_789)  // more digits than DATETIME(6) keeps
        await homeManager.addEntityHistory(EntityStorageItem(entityId: id, timestamp: timestamp, temperatureInC: Measurement(value: 20, unit: .celsius)))
        // the persist queue writes asynchronously: poll the database, bounded
        var stored: [EntityStorageItem] = []
        for _ in 0..<500 where stored.isEmpty {
            stored = try await repository.getHistory(for: id, startDate: nil, endDate: nil, cursor: nil, limit: 10)
            if stored.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        }

        let history = await homeManager.getFullEntityHistory(with: id, limit: 10)

        XCTAssertEqual(history.count, 1)
    }

    /// A text longer than its column is cut instead of failing the insert.
    func testOverlongTextsAreCutToTheColumnWidth() async throws {
        let journal = app.journalRepository
        let long = String(repeating: "ä", count: 2_000)
        try await journal.addPush(JournalPush(timestamp: Date(timeIntervalSince1970: 1_000), runId: nil, title: long, message: long, pushId: "p"))
        let entity = EntityDbItem(placeId: "Hall", serviceName: "Color", characteristicType: CharacteristicsType.color.rawValue, characteristicsName: nil)
        try await entity.save(on: app.db)
        try await EntityChangeDbItem(entityId: entity.requireID(), timestamp: Date(timeIntervalSince1970: 1_000), value: .text(long), origin: "homekit").save(on: app.db)

        let pushes = try await journal.pushes(runId: nil)
        XCTAssertEqual(pushes.first?.title.unicodeScalars.count, JournalDbItem.titleLimit)
        XCTAssertEqual(pushes.first?.message.unicodeScalars.count, JournalDbItem.detailLimit)
        let change = try await EntityChangeDbItem.query(on: app.db).first()
        XCTAssertEqual(change?.text?.unicodeScalars.count, EntityChangeDbItem.textLimit)
    }

    /// The journal cleanup deletes in batches per kind, keeps heating commands and newer rows, and ends.
    func testJournalCleanupDeletesMoreThanOneBatchAndKeepsWhatStays() async throws {
        let journal = app.journalRepository
        let kitchen = EntityId(placeId: "Kitchen", name: "Radiator", characteristicsName: nil, characteristic: .targetTemperature)
        let old = Date(timeIntervalSince1970: 1_000)
        let pushes = (0...2 * JournalDbRepository.deleteBatchSize).map { _ in
            JournalDbItem(JournalPush(timestamp: old, runId: nil, title: "t", message: "m", pushId: "p"))
        }
        for chunk in stride(from: 0, to: pushes.count, by: 2_000) {
            try await pushes[chunk..<min(chunk + 2_000, pushes.count)].create(on: app.db)
        }
        let run = AutomationRun(automationName: "Old", startedAt: old, trigger: AutomationTrigger(kind: .time, entityId: nil, summary: "s"), outcome: .completed)
        try await journal.add(run)
        try await journal.addCommand(ActionLogItem(timestamp: old, action: .setTargetTemperature(kitchen, celsius: 21), reason: .plan))
        try await journal.addCommand(ActionLogItem(timestamp: old, action: .setTargetTemperature(kitchen, celsius: 18)))
        try await journal.addPush(JournalPush(timestamp: Date(), runId: nil, title: "new", message: "m", pushId: "p"))

        try await journal.deleteEntries(olderThan: Date().addingTimeInterval(-60))

        let remainingPushes = try await journal.pushes(runId: nil)
        XCTAssertEqual(remainingPushes.map(\.title), ["new"])
        let remainingRuns = try await journal.latestRunPerAutomation()
        XCTAssertTrue(remainingRuns.isEmpty)
        let commands = try await journal.commands(limit: nil, runId: nil)
        XCTAssertEqual(commands.map(\.reason), [.plan])
    }

    // MARK: - schema

    private func columns(_ query: SQLQueryString) async throws -> [String] {
        let sql = try XCTUnwrap(app.db as? SQLDatabase)
        return try await sql.raw(query).all().map { try $0.decode(column: "v", as: String.self) }
    }

    /// The indexes of the big table are exactly the primary key and the two named ones: the foreign key made no extra one.
    func testEntityChangesHasExactlyTheExpectedIndexes() async throws {
        let names = try await columns("SELECT DISTINCT INDEX_NAME AS v FROM information_schema.statistics WHERE TABLE_SCHEMA = 't' AND TABLE_NAME = 'entityChanges'")
        XCTAssertEqual(names.sorted(), ["PRIMARY", "idx_entityChanges_entity_timestamp", "idx_entityChanges_timestamp_entity"])
        let covering = try await columns("SELECT COLUMN_NAME AS v FROM information_schema.statistics WHERE TABLE_SCHEMA = 't' AND TABLE_NAME = 'entityChanges' AND INDEX_NAME = 'idx_entityChanges_timestamp_entity' ORDER BY SEQ_IN_INDEX")
        XCTAssertEqual(covering, ["timestamp", "entityId"])
    }

    func testJournalIndexesMatchTheQueries() async throws {
        let names = try await columns("SELECT DISTINCT INDEX_NAME AS v FROM information_schema.statistics WHERE TABLE_SCHEMA = 't' AND TABLE_NAME = 'journal'")
        XCTAssertEqual(names.sorted(), ["PRIMARY", "idx_journal_kind_place_timestamp", "idx_journal_kind_timestamp", "idx_journal_kind_title_timestamp", "idx_journal_runId"])
    }

    func testChangeKeyIsABigIntAndTextColumnsAreBinaryCollated() async throws {
        let type = try await columns("SELECT DATA_TYPE AS v FROM information_schema.columns WHERE TABLE_SCHEMA = 't' AND TABLE_NAME = 'entityChanges' AND COLUMN_NAME = 'id'")
        XCTAssertEqual(type, ["bigint"])
        let collations = try await columns("SELECT DISTINCT COLLATION_NAME AS v FROM information_schema.columns WHERE TABLE_SCHEMA = 't' AND TABLE_NAME <> '_fluent_migrations' AND COLLATION_NAME IS NOT NULL")
        XCTAssertEqual(collations, ["utf8mb4_0900_bin"])
        let weather = try await columns("SELECT DATA_TYPE AS v FROM information_schema.columns WHERE TABLE_SCHEMA = 't' AND TABLE_NAME = 'weatherHours' AND COLUMN_NAME = 'temperature2mC'")
        XCTAssertEqual(weather, ["double"])
        let kind = try await columns("SELECT CHARACTER_MAXIMUM_LENGTH AS v FROM information_schema.columns WHERE TABLE_SCHEMA = 't' AND TABLE_NAME = 'journal' AND COLUMN_NAME = 'kind'")
        XCTAssertEqual(kind, ["16"])
    }

    func testAChangeWithoutNumberAndTextIsRefused() async throws {
        let entity = EntityDbItem(placeId: "Hall", serviceName: "Lamp", characteristicType: CharacteristicsType.switcher.rawValue, characteristicsName: nil)
        try await entity.save(on: app.db)
        let empty = try EntityChangeDbItem(entityId: entity.requireID(), timestamp: Date(timeIntervalSince1970: 1), value: .number(1), origin: "homekit")
        empty.number = nil

        do {
            try await empty.save(on: app.db)
            XCTFail("the check constraint should refuse a row without a value")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testAnEntityWithChangesCannotBeDeleted() async throws {
        let id = EntityId(placeId: "Hall", name: "Lamp", characteristicsName: nil, characteristic: .switcher)
        try await app.entityStorageDbRepository.add(EntityStorageItem(entityId: id, timestamp: Date(timeIntervalSince1970: 1), isDeviceOn: true))
        let entity = try await EntityDbItem.query(on: app.db).first()

        do {
            try await XCTUnwrap(entity).delete(on: app.db)
            XCTFail("the foreign key should refuse the delete (RESTRICT)")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    // MARK: - query plans

    /// The tabular `EXPLAIN` of a statement as one text (every row's `select_type`, `key` and `Extra`); the tests below
    /// assert that an index is used, so a later schema edit cannot silently drop one.
    /// The tabular `EXPLAIN` of a statement as one text (every row's `key` and `Extra`); the tests below assert that an
    /// index is used, so a later schema edit cannot silently drop one. It goes through the driver's text protocol:
    /// over the prepared-statement path `sql.raw` uses, MySQLNIO returns no rows for an EXPLAIN (and asserts on EXPLAIN DELETE).
    private func plan(_ statement: String) async throws -> String {
        let mysql = try XCTUnwrap(app.db as? MySQLDatabase)
        let rows = try await mysql.simpleQuery("EXPLAIN " + statement).get()
        XCTAssertFalse(rows.isEmpty, "EXPLAIN returned no rows for \(statement)")
        return rows.map { row in
            "key=\(row.column("key")?.string ?? "-") extra=\(row.column("Extra")?.string ?? "-")"
        }.joined(separator: "\n")
    }

    func testQueryPlansUseTheIndexes() async throws {
        let id = EntityId(placeId: "Hall", name: "Lamp", characteristicsName: nil, characteristic: .switcher)
        try await app.entityStorageDbRepository.add(EntityStorageItem(entityId: id, timestamp: Date(timeIntervalSince1970: 1), isDeviceOn: true))
        try await app.journalRepository.addCommand(ActionLogItem(timestamp: Date(timeIntervalSince1970: 1), action: .setTargetTemperature(id, celsius: 21), reason: .plan))
        let history = try await plan("SELECT * FROM entityChanges WHERE entityId = UNHEX(REPEAT('00', 16)) AND timestamp < '2030-01-01' ORDER BY timestamp DESC, id DESC LIMIT 10")
        XCTAssertTrue(history.contains("idx_entityChanges_entity_timestamp"), history)
        XCTAssertFalse(history.contains("filesort"), history)
        let newest = try await plan("SELECT newest.id FROM entities e, LATERAL (SELECT c.id FROM entityChanges c WHERE c.entityId = e.id ORDER BY c.timestamp DESC, c.id DESC LIMIT 1) AS newest")
        XCTAssertTrue(newest.contains("idx_entityChanges_entity_timestamp"), newest)
        let heating = try await plan("SELECT * FROM journal WHERE kind = 'command' AND entityPlaceId = 'Hall' AND timestamp >= '2020-01-01' ORDER BY timestamp")
        XCTAssertTrue(heating.contains("idx_journal_kind_place_timestamp"), heating)
        let cleanup = try await plan("DELETE FROM journal WHERE kind = 'push' AND timestamp < '2020-01-01' ORDER BY timestamp LIMIT 5000")
        XCTAssertTrue(cleanup.contains("idx_journal_kind_timestamp"), cleanup)
        let runs = try await plan("SELECT * FROM journal WHERE kind = 'run' AND title = 'x' ORDER BY timestamp DESC LIMIT 1")
        XCTAssertTrue(runs.contains("idx_journal_kind_title_timestamp"), runs)
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
        func command(_ id: EntityId, at seconds: Double, reason: HeatingWriteReason?) -> ActionLogItem {
            ActionLogItem(timestamp: Date(timeIntervalSince1970: seconds), action: .setTargetTemperature(id, celsius: 21), reason: reason)
        }
        try await repository.addCommand(command(kitchen, at: 3_000, reason: .system))
        try await repository.addCommand(command(kitchen, at: 1_000, reason: .plan))
        try await repository.addCommand(command(kitchen, at: 2_000, reason: .window))
        try await repository.addCommand(command(kitchen, at: 2_500, reason: nil))
        try await repository.addCommand(command(bath, at: 2_000, reason: .plan))

        let all = try await repository.heatingWrites(placeId: "Kitchen", startDate: nil, endDate: nil)
        XCTAssertEqual(all.map(\.reason), [.plan, .window, .system])
        XCTAssertEqual(all.first?.value, 21)
        let lastPerRadiator = try await repository.lastHeatingWrites()
        XCTAssertEqual(Set(lastPerRadiator.map(\.entityId.placeId)), ["Kitchen", "Bath"])

        let ranged = try await repository.heatingWrites(placeId: "Kitchen", startDate: Date(timeIntervalSince1970: 1_500), endDate: Date(timeIntervalSince1970: 3_000))
        XCTAssertEqual(ranged.map(\.reason), [.window])
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

//
//  EntityStorageMySQLTests.swift
//  HomeAutomation
//
//  Runs only against a throwaway MySQL: set HA_TEST_MYSQL_PORT (host 127.0.0.1, database `t`, user `u`, password `p`), e.g.
//  docker run --rm -p 33307:3306 -e MYSQL_ROOT_PASSWORD=x -e MYSQL_DATABASE=t -e MYSQL_USER=u -e MYSQL_PASSWORD=p mysql:9
//  Never point it at a real database: it creates and fills the tables.

import Fluent
import FluentMySQLDriver
import SQLKit
@testable import HAModels
@testable import Server
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
        app.migrations.add(CreateWeatherSnapshot())
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
        for (offset, values) in [(0, (0, 0)), (1, (3, 100)), (2, (nil, nil))] as [(Int, (Int?, Int?))] {
            try await repository.add(EntityStorageItem(entityId: id, timestamp: Date(timeIntervalSince1970: Double(1_000 + offset)),
                                                       heatingMode: values.0, valvePositionPercent: values.1))
        }

        let items = try await repository.getHistory(for: id, startDate: nil, endDate: nil, cursor: nil, limit: 10)

        XCTAssertEqual(items.map(\.heatingMode), [nil, 3, 0])
        XCTAssertEqual(items.map(\.valvePositionPercent), [nil, 100, 0])
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
        let a = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: "Thermostat", characteristic: .temperatureSensor)
        let b = EntityId(placeId: "Kitchen", name: "Thermo", characteristicsName: "Thermostat", characteristic: .valvePosition)
        let c = EntityId(placeId: "Hall", name: "Lamp", characteristicsName: nil, characteristic: .switcher)
        for (index, id) in [a, a, b, c].enumerated() {
            try await repository.add(EntityStorageItem(entityId: id, timestamp: Date(timeIntervalSince1970: Double(index)), isDeviceOn: true))
        }

        let ids = try await repository.getAllEntityIds()

        XCTAssertEqual(ids.count, 3)
        XCTAssertEqual(Set(ids.map(\.description)), Set([a, b, c].map(\.description)))
        XCTAssertEqual(ids.first { $0.characteristicType == .valvePosition }?.characteristicsName, "Thermostat")
        XCTAssertNil(ids.first { $0.characteristicType == .switcher }?.characteristicsName)
    }
}

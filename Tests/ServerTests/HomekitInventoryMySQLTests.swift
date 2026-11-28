//
//  HomekitInventoryMySQLTests.swift
//  HomeAutomationServer
//
//  Runs only against a throwaway MySQL, like `EntityStorageMySQLTests` (HA_TEST_MYSQL_PORT).

import Fluent
import FluentMySQLDriver
import HAImplementations
@testable import HAModels
@testable import Server
import SQLKit
import XCTVapor

final class HomekitInventoryMySQLTests: XCTestCase {
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

    private typealias Item = HomekitInventoryTests

    private func strings(_ query: SQLQueryString) async throws -> [String] {
        let sql = try XCTUnwrap(app.db as? SQLDatabase)
        return try await sql.raw(query).all().map { try $0.decode(column: "v", as: String.self) }
    }

    func testAReplaceSwapsTheWholeSnapshot() async throws {
        let repository = app.homekitInventoryRepository
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        try await repository.replace(with: Item.inventory([("Bad", Item.accessory("A", characteristics: [Item.characteristic()])), ("Bad", Item.accessory("B", characteristics: [Item.characteristic()]))]), syncedAt: first)
        var rows = try await repository.all()
        XCTAssertEqual(rows.map(\.accessoryName), ["A", "B"])

        let second = first.addingTimeInterval(60)
        try await repository.replace(with: Item.inventory([("Bad", Item.accessory("C", characteristics: [Item.characteristic(type: nil, value: nil)]))]), syncedAt: second)
        rows = try await repository.all()

        XCTAssertEqual(rows.map(\.accessoryName), ["C"])
        XCTAssertNil(rows.first?.mappedType)
        XCTAssertNil(rows.first?.value)
        XCTAssertEqual(rows.first?.syncedAt.timeIntervalSince1970 ?? 0, second.timeIntervalSince1970, accuracy: 1)
    }

    func testAFailedReplaceKeepsTheOldSnapshot() async throws {
        let repository = app.homekitInventoryRepository
        func one(_ name: String) -> HomeKitInventory { Item.inventory([("Bad", Item.accessory(name, characteristics: [Item.characteristic()]))]) }
        try await repository.replace(with: one("Old"), syncedAt: Date())
        // a NUL-free but over-wide room name is fitted; an invalid mapped type cannot be made, so force a failure with a duplicate id
        let sql = try XCTUnwrap(app.db as? SQLDatabase)
        try await sql.raw("ALTER TABLE homekitInventory ADD CONSTRAINT chk_fail CHECK (accessoryName <> 'Boom')").run()
        do {
            try await repository.replace(with: Item.inventory([("Bad", Item.accessory("New", characteristics: [Item.characteristic()])), ("Bad", Item.accessory("Boom", characteristics: [Item.characteristic()]))]), syncedAt: Date())
            XCTFail("expected a failure")
        } catch {}
        let names = try await repository.all().map(\.accessoryName)
        XCTAssertEqual(names, ["Old"])
    }

    func testIndexesAndBinaryCollation() async throws {
        let names = try await strings("SELECT DISTINCT INDEX_NAME AS v FROM information_schema.statistics WHERE TABLE_SCHEMA = 't' AND TABLE_NAME = 'homekitInventory'")
        XCTAssertEqual(names.sorted(), ["PRIMARY", "idx_homekitInventory_mappedType_room_accessory", "idx_homekitInventory_room_accessory"])
        let collations = try await strings("SELECT DISTINCT COLLATION_NAME AS v FROM information_schema.columns WHERE TABLE_SCHEMA = 't' AND TABLE_NAME = 'homekitInventory' AND COLLATION_NAME IS NOT NULL")
        XCTAssertEqual(collations, ["utf8mb4_0900_bin"])
    }

    /// The query of `docs/database-schema.md`: contact sensors of HomeKit that no stored automation references.
    func testTheDocumentedQueryFindsContactSensorsMissingFromTheAutomations() async throws {
        let known = ContactSensorDevice(contactSensorId: EntityId(placeId: "Bad", name: "Fenster_1", characteristicsName: nil, characteristic: .contactSensor), batterySensorId: nil)
        let automation = AnyAutomation.create(from: WindowOpen("window", windowContact: known))
        let config = ConfigDTO(location: Location(latitude: 52.5, longitude: 13.4), automations: [automation])
        try await ConfigItem.save(json: try JSONEncoder().encode(config), on: app.db)
        func contact(_ type: CharacteristicsType = .contactSensor) -> [HomeKitInventory.Characteristic] { [Item.characteristic(type: type)] }
        try await app.homekitInventoryRepository.replace(with: Item.inventory([
            ("Bad", Item.accessory("Fenster_1", characteristics: contact())),
            ("Bad", Item.accessory("FensterX1", characteristics: contact())),   // `_` must not act as a wildcard
            ("Küche", Item.accessory("Fenster", characteristics: contact())),
            ("Küche", Item.accessory("Lampe", characteristics: contact(.switcher)))
        ]), syncedAt: Date())

        let missing = try await strings(SQLQueryString(Self.missingContactSensorsQuery))

        XCTAssertEqual(missing, ["Bad / FensterX1", "Küche / Fenster"])
    }

    func testTheCharacteristicsPerRoomQuery() async throws {
        try await app.homekitInventoryRepository.replace(with: Item.inventory([
            ("Bad", Item.accessory("A", characteristics: [Item.characteristic()])),
            ("Bad", Item.accessory("B", characteristics: [Item.characteristic(type: nil)])),
            ("Küche", Item.accessory("C", characteristics: [Item.characteristic()]))
        ]), syncedAt: Date())
        let rows = try await strings(SQLQueryString("SELECT CONCAT(roomName, ': ', COUNT(*), ' / ', SUM(mappedType IS NULL)) AS v FROM homekitInventory GROUP BY roomName ORDER BY roomName"))
        XCTAssertEqual(rows, ["Bad: 2 / 1", "Küche: 1 / 0"])
    }

    /// Keep in sync with `docs/database-schema.md`.
    static let missingContactSensorsQuery = """
        WITH cfg AS (
          -- the config blob holds the JSON as base64 text in quotes (how the server writes it) or as plain JSON
          SELECT CAST(IF(LEFT(s, 1) = '"', CONVERT(FROM_BASE64(JSON_UNQUOTE(s)) USING utf8mb4), s) AS JSON) AS doc
          FROM (SELECT CONVERT(json USING utf8mb4) AS s FROM config) raw
        )
        SELECT CONCAT(i.roomName, ' / ', i.accessoryName) AS v
        FROM homekitInventory i
        WHERE i.mappedType = 'contactSensor'
          AND NOT EXISTS (
            SELECT 1 FROM cfg
            WHERE JSON_SEARCH(cfg.doc, 'one',
                    REPLACE(REPLACE(REPLACE(i.accessoryName, '|', '||'), '%', '|%'), '_', '|_'), '|', '$**.contactSensorId.name') IS NOT NULL
              AND JSON_SEARCH(cfg.doc, 'one',
                    REPLACE(REPLACE(REPLACE(i.roomName, '|', '||'), '%', '|%'), '_', '|_'), '|', '$**.contactSensorId.placeId') IS NOT NULL)
        GROUP BY i.roomName, i.accessoryName
        ORDER BY i.roomName, i.accessoryName
        """
}

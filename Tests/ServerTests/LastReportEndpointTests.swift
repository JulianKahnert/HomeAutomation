//
//  LastReportEndpointTests.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAApplicationLayer
@testable import HAImplementations
@testable import HAModels
@testable import Server
import SQLKit
@testable import StarActorSystem
import XCTVapor

/// `/health` and the history route carry the time of the last report, kept in memory by the home manager.
final class LastReportEndpointTests: XCTestCase {
    var app: Application!
    private let token = "last-report-test-token"
    private var homeManager: HomeManager!
    private let switchId = EntityId(placeId: "Bad - OG", name: "Licht", characteristicsName: nil, characteristic: .switcher)
    private let changedAt = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() async throws {
        app = try await Application.make(.testing)
        app.environment.arguments = ["serve"]
        app.authToken = token
        app.authDisabled = false
        app.homeAutomationConfigService = HomeAutomationConfigService(location: Location(latitude: 52.52, longitude: 13.405), persist: { _ in })
        app.automationService = try await makeAutomationService(automations: [])
        app.starActorSystem = StarActorSystem(name: "last-report-tests")
        let entityKey = UUID()
        let entityRow: [String: any Sendable] = ["id": entityKey, "placeId": switchId.placeId, "serviceName": switchId.name,
                                                 "characteristicType": switchId.characteristicType.rawValue,
                                                 "characteristicsName": String?.none]
        let changeRow: [String: any Sendable] = ["id": UUID(), "entityId": entityKey, "timestamp": changedAt,
                                                 "number": Double?.some(1), "text": String?.none, "origin": Origin.homekit.rawValue]
        app.databases.use(InMemoryDatabaseConfiguration(rows: [EntityDbItem.schema: [entityRow],
                                                               EntityChangeDbItem.schema: [changeRow]]),
                          as: DatabaseID(string: "in-memory"), isDefault: true)
        homeManager = await HomeManager(getAdapter: { nil },
                                        storageRepo: EmptyStorage(),
                                        notificationSender: SilentSender(),
                                        location: Location(latitude: 52.52, longitude: 13.405))
        app.homeManager = homeManager
        try routes(app)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    private func get(_ path: String) async throws -> (HTTPStatus, Data) {
        var status: HTTPStatus = .internalServerError
        var body = Data()
        try await app.test(.GET, path, beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
        }, afterResponse: { res async in
            status = res.status
            body = Data(res.body.readableBytesView)
        })
        return (status, body)
    }

    func testHealthListsTheLastReportPerSource() async throws {
        try await adapterIsUp()
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: changedAt, isDeviceOn: true))
        let valve = EntityId(placeId: "Bad - OG", name: "Thermo", characteristicsName: nil, characteristic: .valve)
        await homeManager.addEntityHistory(EntityStorageItem(entityId: valve, timestamp: changedAt, valveOpen: true, origin: .job("ValveJob")))
        let reports = await homeManager.lastReports()

        let (status, body) = try await get("/health")

        XCTAssertEqual(status, .ok, String(decoding: body, as: UTF8.self))
        let health = try JSONDecoder().decode(Health.self, from: body)
        XCTAssertEqual(Set(health.lastReports.keys), ["homekit", "ValveJob"])
        XCTAssertEqual(health.lastReports["homekit"], reports["homekit"]?.formatted(.iso8601))
        XCTAssertEqual(health.lastReports["ValveJob"], reports["ValveJob"]?.formatted(.iso8601))
    }

    func testHealthListsNoSourceBeforeTheFirstReport() async throws {
        try await adapterIsUp()

        let (status, body) = try await get("/health")

        XCTAssertEqual(status, .ok, String(decoding: body, as: UTF8.self))
        XCTAssertEqual(try JSONDecoder().decode(Health.self, from: body).lastReports, [:])
    }

    func testHistoryCarriesTheLastReportOnTheCurrentState() async throws {
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: changedAt, isDeviceOn: true))
        // a replay: the state stays, the report is newer
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: changedAt.addingTimeInterval(600), isDeviceOn: true))
        let reported = await homeManager.lastReport(of: switchId)
        let lastReport = try XCTUnwrap(reported)

        let (status, body) = try await get("/entities/history?placeId=Bad%20-%20OG&name=Licht&characteristicType=switcher")

        XCTAssertEqual(status, .ok, String(decoding: body, as: UTF8.self))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let history = try decoder.decode(History.self, from: body)
        XCTAssertEqual(history.items.count, 1)
        XCTAssertEqual(history.items.first?.timestamp, changedAt)
        XCTAssertEqual(try XCTUnwrap(history.items.first?.lastReport).timeIntervalSince1970, lastReport.timeIntervalSince1970, accuracy: 1)
    }

    func testHistoryHasNoLastReportBeforeTheFirstReport() async throws {
        let (status, body) = try await get("/entities/history?placeId=Bad%20-%20OG&name=Licht&characteristicType=switcher")

        XCTAssertEqual(status, .ok, String(decoding: body, as: UTF8.self))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let history = try decoder.decode(History.self, from: body)
        XCTAssertEqual(history.items.count, 1)
        XCTAssertNil(history.items.first?.lastReport)
    }

    /// The adapter link reaches `.up` once the peer's hello arrived.
    private func adapterIsUp() async throws {
        let system = app.starActorSystem
        let connection = SilentConnection()
        await system.attach(connection)
        let hello = try JSONEncoder().encode(WireEnvelope.hello(Hello(protocolVersion: StarActorSystem.protocolVersion)))
        await system.receive(hello, from: connection)
        XCTAssertEqual(system.latestConnectionStatus, .up)
    }

    private struct Health: Decodable {
        let lastReports: [String: String]
    }

    private struct History: Decodable {
        struct Item: Decodable {
            let timestamp: Date
            let lastReport: Date?
        }
        let items: [Item]
    }
}

/// A link to the adapter that swallows every frame.
private final class SilentConnection: WireConnection, @unchecked Sendable {
    func send(_ data: Data) async throws {}
    func close() async {}
}

// MARK: - In-memory database

/// Answers every Fluent query with the fixed rows of its table (filters, sorting and limits ignored)
/// and every raw SQL statement with no rows, so the routes run without MySQL.
private struct InMemoryDatabaseConfiguration: DatabaseConfiguration {
    var middleware: [any AnyModelMiddleware] = []
    let rows: [String: [[String: any Sendable]]]

    func makeDriver(for databases: Databases) -> any DatabaseDriver {
        InMemoryDriver(rows: rows)
    }
}

private struct InMemoryDriver: DatabaseDriver {
    let rows: [String: [[String: any Sendable]]]

    func makeDatabase(with context: DatabaseContext) -> any Database {
        InMemoryDatabase(context: context, rows: rows)
    }

    func shutdown() {}
}

private struct InMemoryDatabase: Database, SQLDatabase {
    let context: DatabaseContext
    let rows: [String: [[String: any Sendable]]]

    var logger: Logger { context.logger }
    var eventLoop: any EventLoop { context.eventLoop }
    var dialect: any SQLDialect { InMemoryDialect() }
    var inTransaction: Bool { false }

    func execute(query: DatabaseQuery, onOutput: @escaping @Sendable (any DatabaseOutput) -> Void) -> EventLoopFuture<Void> {
        let rows = rows[query.schema] ?? []
        // Fluent expects every output on the event loop.
        return eventLoop.submit {
            for row in rows {
                onOutput(InMemoryOutput(values: row))
            }
        }
    }

    func execute(schema: DatabaseSchema) -> EventLoopFuture<Void> { eventLoop.makeSucceededVoidFuture() }
    func execute(enum: DatabaseEnum) -> EventLoopFuture<Void> { eventLoop.makeSucceededVoidFuture() }

    func execute(sql query: any SQLExpression, _ onRow: @escaping @Sendable (any SQLRow) -> Void) -> EventLoopFuture<Void> {
        eventLoop.makeSucceededVoidFuture()
    }

    func transaction<T>(_ closure: @escaping @Sendable (any Database) -> EventLoopFuture<T>) -> EventLoopFuture<T> { closure(self) }
    func withConnection<T>(_ closure: @escaping @Sendable (any Database) -> EventLoopFuture<T>) -> EventLoopFuture<T> { closure(self) }
}

private struct InMemoryDialect: SQLDialect {
    var name: String { "in-memory" }
    var identifierQuote: any SQLExpression { SQLRaw("`") }
    var supportsAutoIncrement: Bool { false }
    var autoIncrementClause: any SQLExpression { SQLRaw("") }
    func bindPlaceholder(at position: Int) -> any SQLExpression { SQLRaw("?") }
    func literalBoolean(_ value: Bool) -> any SQLExpression { SQLRaw(value ? "1" : "0") }
}

private struct InMemoryOutput: DatabaseOutput {
    let values: [String: any Sendable]

    var description: String { "\(values)" }

    func schema(_ schema: String) -> any DatabaseOutput { self }

    func contains(_ key: FieldKey) -> Bool { values[key.description] != nil }

    func decodeNil(_ key: FieldKey) throws -> Bool {
        guard let value = values[key.description] else { return true }
        let mirror = Mirror(reflecting: value)
        return mirror.displayStyle == .optional && mirror.children.isEmpty
    }

    func decode<T: Decodable>(_ key: FieldKey, as type: T.Type) throws -> T {
        guard let value = values[key.description] as? T else {
            throw DecodingError.typeMismatch(T.self, .init(codingPath: [], debugDescription: "no \(T.self) at \(key)"))
        }
        return value
    }
}

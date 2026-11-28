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

/// `/health` carries the last report per source (memory of the home manager); the history route the stored last report of the entity.
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
        let changeRow: [String: any Sendable] = ["id": 1, "entityId": entityKey, "timestamp": changedAt,
                                                 "number": Double?.some(1), "text": String?.none, "origin": Origin.homekit.rawValue]
        app.databases.use(InMemoryDatabaseConfiguration(rows: [EntityDbItem.schema: [entityRow],
                                                               EntityChangeDbItem.schema: [changeRow]]),
                          as: DatabaseID(string: "in-memory"), isDefault: true)
        homeManager = await HomeManager(getAdapter: { nil },
                                        storageRepo: MemoryStorage(),
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

    func testHistoryCarriesTheStoredLastReportOnTheNewestChangeOnly() async throws {
        let lastReport = changedAt.addingTimeInterval(600)
        let older = EntityStorageItem(entityId: switchId, timestamp: changedAt.addingTimeInterval(-3600), isDeviceOn: false)
        let newest = EntityStorageItem(entityId: switchId, timestamp: changedAt, isDeviceOn: true, lastReport: lastReport)
        // no core: the answer comes from storage alone
        app.storageReader = MemoryStorage(seed: [older, newest])

        let (status, body) = try await get("/entities/history?placeId=Bad%20-%20OG&name=Licht&characteristicType=switcher")

        XCTAssertEqual(status, .ok, String(decoding: body, as: UTF8.self))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let history = try decoder.decode(History.self, from: body)
        XCTAssertEqual(history.items.count, 2)
        XCTAssertEqual(try XCTUnwrap(history.items.first?.lastReport).timeIntervalSince1970, lastReport.timeIntervalSince1970, accuracy: 1)
        XCTAssertNil(history.items.last?.lastReport)
    }

    func testTheNewestChangeCountsAsTheLastReportBeforeAnyStoredReport() async throws {
        let (status, body) = try await get("/entities/history?placeId=Bad%20-%20OG&name=Licht&characteristicType=switcher")

        XCTAssertEqual(status, .ok, String(decoding: body, as: UTF8.self))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let history = try decoder.decode(History.self, from: body)
        XCTAssertEqual(history.items.count, 1)
        // no stored report time: the change's own timestamp counts as the report
        XCTAssertEqual(try XCTUnwrap(history.items.first?.lastReport).timeIntervalSince1970, changedAt.timeIntervalSince1970, accuracy: 1)
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

//
//  ServerOwnedEntityTests.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAApplicationLayer
@testable import HAImplementations
@testable import HAModels
@testable import Server
import StarActorSystem
import Synchronization
import XCTVapor

final class ServerOwnedEntityTests: XCTestCase {
    var app: Application!
    private let token = "server-owned-test-token"

    override func setUp() async throws {
        app = try await Application.make(.testing)
        app.environment.arguments = ["serve"]
        app.authToken = token
        app.authDisabled = false
        app.homeAutomationConfigService = HomeAutomationConfigService(location: Location(latitude: 52.52, longitude: 13.405), persist: { _ in })
        app.automationService = try await makeAutomationService(automations: [])
        app.starActorSystem = StarActorSystem(name: "server-owned-tests")
        let (stream, continuation) = AsyncStream.makeStream(of: HomeEvent.self)
        app.homeEventsStream = stream
        app.homeEventsContinuation = continuation
        app.databases.use(InMemoryDatabaseConfiguration(), as: DatabaseID(string: "in-memory"), isDefault: true)
        // no adapter: a server-owned entity needs none, a HomeKit entity cannot be checked
        app.homeManager = await HomeManager(getAdapter: { nil },
                                            storageRepo: EmptyStorage(),
                                            notificationSender: SilentSender(),
                                            location: Location(latitude: 52.52, longitude: 13.405))
        try routes(app)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    private func deploy(naming entityId: EntityId) async throws -> HTTPStatus {
        let window = WindowOpen("window", windowContact: ContactSensorDevice(contactSensorId: entityId, batterySensorId: nil))
        let dto = ConfigDTO(location: Location(latitude: 52.52, longitude: 13.405), automations: [AnyAutomation.create(from: window)])
        let body = try JSONEncoder().encode(dto)
        var status: HTTPStatus = .internalServerError
        try await app.test(.POST, "/config", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            req.headers.contentType = .json
            req.body = ByteBuffer(data: body)
        }, afterResponse: { res async in status = res.status })
        return status
    }

    func testDeployAcceptsAConfigThatNamesAServerOwnedEntity() async throws {
        let status = try await deploy(naming: .serverOwned(name: "holiday", characteristic: .contactSensor))
        XCTAssertEqual(status, .ok)
    }

    func testDeployStillChecksAHomeKitEntity() async throws {
        let status = try await deploy(naming: EntityId(placeId: "room", name: "contact", characteristicsName: nil, characteristic: .contactSensor))
        XCTAssertNotEqual(status, .ok)
    }

    func testAReportedChangeReachesAnAutomationOnceWithOriginServer() async throws {
        let holiday = EntityId.serverOwned(name: "holiday", characteristic: .switcher)
        let (stream, continuation) = AsyncStream.makeStream(of: HomeEvent.self)
        // wired like configure.swift
        let homeManager = await HomeManager(getAdapter: { nil },
                                            storageRepo: EmptyStorage(),
                                            notificationSender: SilentSender(),
                                            location: Location(latitude: 52.52, longitude: 13.405),
                                            onReportedChange: { continuation.yield(.change(entity: $0)) })
        let seen = Mutex<[EntityStorageItem]>([])
        let automation = RecordingAutomation(entityId: holiday, onTrigger: { item in seen.withLock { $0.append(item) } })
        let automationService = try AutomationService(using: homeManager, runs: NoRuns(), automations: [automation])
        let loop = Task {
            await HomeEventProcessingJob(gauge: EventLoopGauge(), homeEventsStream: stream,
                                         automationService: automationService, homeManager: homeManager).run()
        }
        defer { loop.cancel() }

        try await homeManager.report(holiday, value: .bool(true))
        // unchanged: no event
        try await homeManager.report(holiday, value: .bool(true))
        try await homeManager.report(holiday, value: .bool(false))
        // a polling job reports with its own origin and is checked at the source just the same
        try await homeManager.report(holiday, value: .bool(true), origin: .job("EnergyPriceJob"))
        try await waitUntil { seen.withLock { $0.count } >= 3 }
        await automationService.waitUntilIdle()

        // Each change arrives once. A second check in the loop would find the state already set and drop the event.
        let items = seen.withLock { $0 }
        XCTAssertEqual(items.map(\.isDeviceOn), [true, false, true])
        XCTAssertEqual(items.map(\.origin), [.server, .server, .job("EnergyPriceJob")])
    }

    func testAReportedStateAppearsInTheHistoryRoute() async throws {
        let holiday = EntityId.serverOwned(name: "holiday", characteristic: .switcher)
        let homeManager = await HomeManager(getAdapter: { nil },
                                            storageRepo: app.entityStorageDbRepository,
                                            notificationSender: SilentSender(),
                                            location: Location(latitude: 52.52, longitude: 13.405))
        app.homeManager = homeManager

        try await homeManager.report(holiday, value: .bool(true))

        // the background queue stores the report
        var body = Data()
        try await waitUntil {
            body = try await self.get("/entities/history?placeId=server&name=holiday&characteristicType=switcher")
            return try JSONDecoder().decode(History.self, from: body).items.isEmpty == false
        }
        let history = try JSONDecoder().decode(History.self, from: body)
        XCTAssertEqual(history.items.count, 1)
        XCTAssertEqual(history.items.first?.valueKind, "switcher")
        XCTAssertEqual(history.items.first?.value, true)
    }

    private func get(_ path: String) async throws -> Data {
        var body = Data()
        try await app.test(.GET, path, beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
            body = Data(res.body.readableBytesView)
        })
        return body
    }

    private func waitUntil(timeout: Duration = .seconds(30), _ condition: () async throws -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while try await !condition() {
            guard ContinuousClock.now < deadline else { return XCTFail("condition not met within \(timeout)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private struct History: Decodable {
        struct Item: Decodable {
            let valueKind: String?
            let value: Bool?
        }
        let items: [Item]
    }
}

/// Triggers on every change of its entity and records it; sees every change, none collapsed.
private struct RecordingAutomation: Automatable {
    var isActive = true
    let name = "recording"
    let entityId: EntityId
    let onTrigger: @Sendable (EntityStorageItem) -> Void
    var triggerEntityIds: Set<EntityId> { [entityId] }
    var lanePolicy: LanePolicy { .runEach }

    init(entityId: EntityId, onTrigger: @escaping @Sendable (EntityStorageItem) -> Void) {
        self.entityId = entityId
        self.onTrigger = onTrigger
    }

    init(from decoder: any Decoder) throws { fatalError("not decoded in tests") }

    func encode(to encoder: any Encoder) throws {}

    func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        guard case .change(let item) = event, item.entityId == entityId else { return false }
        onTrigger(item)
        return false
    }

    func execute(using hm: HomeManagable) async throws {}
}

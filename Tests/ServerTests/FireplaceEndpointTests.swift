//
//  FireplaceEndpointTests.swift
//  HomeAutomationServer
//

import Foundation
import HAApplicationLayer
@testable import HAImplementations
@testable import HAModels
@testable import Server
import StarActorSystem
import XCTVapor

final class FireplaceEndpointTests: XCTestCase {
    var app: Application!
    private let token = "fireplace-test-token"
    private var storage: FireplaceStorage!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        app.environment.arguments = ["serve"]
        app.authToken = token
        app.authDisabled = false
        app.homeAutomationConfigService = HomeAutomationConfigService(location: Location(latitude: 52.52, longitude: 13.405),
                                                                      automations: [], persist: { _ in })
        app.starActorSystem = StarActorSystem(name: "fireplace-tests")
        storage = FireplaceStorage()
        // no adapter: a command fails and is queued, which is all the endpoint needs here
        app.homeManager = await HomeManager(getAdapter: { nil },
                                            storageRepo: storage,
                                            notificationSender: SilentSender(),
                                            location: Location(latitude: 52.52, longitude: 13.405),
                                            actionLogManager: ActionLogManager())
        try routes(app)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    private struct State: Decodable {
        let isOn: Bool
        let since: Date?
        let endsAt: Date?
    }

    private func request(_ method: HTTPMethod, token: String?, body: String? = nil) async throws -> (HTTPStatus, State?) {
        var status: HTTPStatus = .internalServerError
        var state: State?
        try await app.test(method, "/heating/fireplace", beforeRequest: { req in
            if let token { req.headers.add(name: .authorization, value: "Bearer \(token)") }
            if let body {
                req.headers.contentType = .json
                req.body = ByteBuffer(string: body)
            }
        }, afterResponse: { res async in
            status = res.status
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            state = try? decoder.decode(State.self, from: Data(res.body.readableBytesView))
        })
        return (status, state)
    }

    func testGetRequiresAuthentication() async throws {
        let (status, _) = try await request(.GET, token: nil)
        XCTAssertEqual(status, .unauthorized)
    }

    func testPutRequiresAuthentication() async throws {
        let (status, _) = try await request(.PUT, token: "wrong", body: #"{"isOn":true}"#)
        XCTAssertEqual(status, .unauthorized)
    }

    func testUnknownSwitchIsOff() async throws {
        let (status, state) = try await request(.GET, token: token)
        XCTAssertEqual(status, .ok)
        XCTAssertEqual(state?.isOn, false)
        XCTAssertNil(state?.since)
    }

    func testStateSaysSinceAndEnd() async throws {
        let start = Date(timeIntervalSinceNow: -3600)
        await storage.set(EntityStorageItem(entityId: Fireplace.switchId, timestamp: start, isDeviceOn: true))

        let (status, state) = try await request(.GET, token: token)

        XCTAssertEqual(status, .ok)
        XCTAssertEqual(state?.isOn, true)
        XCTAssertEqual(try XCTUnwrap(state?.since).timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(state?.endsAt).timeIntervalSince1970, start.addingTimeInterval(8 * 3600).timeIntervalSince1970, accuracy: 1)
    }

    func testSwitchOnAnswersTheNewState() async throws {
        await storage.set(EntityStorageItem(entityId: Fireplace.switchId, timestamp: Date(timeIntervalSinceNow: -60), isDeviceOn: false))

        let (status, state) = try await request(.PUT, token: token, body: #"{"isOn":true}"#)

        XCTAssertEqual(status, .ok)
        XCTAssertEqual(state?.isOn, true)
        XCTAssertNotNil(state?.endsAt)
    }

    func testSwitchOffAnswersOff() async throws {
        await storage.set(EntityStorageItem(entityId: Fireplace.switchId, timestamp: Date(timeIntervalSinceNow: -60), isDeviceOn: true))

        let (status, state) = try await request(.PUT, token: token, body: #"{"isOn":false}"#)

        XCTAssertEqual(status, .ok)
        XCTAssertEqual(state?.isOn, false)
    }
}

private actor FireplaceStorage: StorageRepository {
    private var items: [EntityStorageItem] = []

    func set(_ item: EntityStorageItem) { items.append(item) }
    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem? { items.last { $0.entityId == entityId } }
    func getPrevious(_ entityId: EntityId) async throws -> EntityStorageItem? { nil }
    func add(_ item: EntityStorageItem) async throws { items.append(item) }
    func getHistory(for entityId: EntityId, startDate: Date?, endDate: Date?, cursor: Date?, limit: Int) async throws -> [EntityStorageItem] { [] }
    func getAllEntityIds() async throws -> [EntityId] { [] }
}

private struct SilentSender: NotificationSender {
    func sendNotification(title: String, message: String, id: String, category: String?) async throws {}
    func clearNotification(id: String) async throws {}
    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState, activityName: String, options: LiveActivityOptions) async {}
    func endAllLiveActivities(ofActivityType activityType: String) async {}
}

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
    private var events: EventLog!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        app.environment.arguments = ["serve"]
        app.authToken = token
        app.authDisabled = false
        app.homeAutomationConfigService = HomeAutomationConfigService(location: Location(latitude: 52.52, longitude: 13.405), persist: { _ in })
        app.automationService = try await makeAutomationService(automations: [])
        app.starActorSystem = StarActorSystem(name: "fireplace-tests")
        events = EventLog()
        // no adapter: the fireplace is the server's own state and needs none
        app.homeManager = await HomeManager(getAdapter: { nil },
                                            storageRepo: EmptyStorage(),
                                            notificationSender: SilentSender(),
                                            location: Location(latitude: 52.52, longitude: 13.405),
                                            onReportedChange: { [events] in events?.append($0) })
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

    private func request(_ method: HTTPMethod, _ path: String = "/heating/fireplace", token: String?, body: String? = nil) async throws -> (HTTPStatus, State?) {
        var status: HTTPStatus = .internalServerError
        var state: State?
        try await app.test(method, path, beforeRequest: { req in
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

    /// The app's way to switch the fireplace: the general route.
    @discardableResult
    private func switchFireplace(_ isOn: Bool) async throws -> HTTPStatus {
        let body = #"{"entityId":{"placeId":"server","name":"fireplace","characteristicType":"switcher"},"value":\#(isOn)}"#
        return try await request(.PUT, "/entities/state", token: token, body: body).0
    }

    func testGetRequiresAuthentication() async throws {
        let (status, _) = try await request(.GET, token: nil)
        XCTAssertEqual(status, .unauthorized)
    }

    func testThePutRouteIsGone() async throws {
        let (status, _) = try await request(.PUT, token: token, body: #"{"isOn":true}"#)
        XCTAssertEqual(status, .notFound)
    }

    func testNeverSwitchedIsOff() async throws {
        let (status, state) = try await request(.GET, token: token)
        XCTAssertEqual(status, .ok)
        XCTAssertEqual(state?.isOn, false)
        XCTAssertNil(state?.since)
    }

    func testSwitchOnHoldsAtOnceAndGetSaysSinceAndEnd() async throws {
        let before = Date()
        let putStatus = try await switchFireplace(true)
        XCTAssertEqual(putStatus, .ok)

        let (status, state) = try await request(.GET, token: token)
        XCTAssertEqual(status, .ok)
        XCTAssertEqual(state?.isOn, true)
        let since = try XCTUnwrap(state?.since)
        XCTAssertEqual(since.timeIntervalSince1970, before.timeIntervalSince1970, accuracy: 5)
        XCTAssertEqual(try XCTUnwrap(state?.endsAt).timeIntervalSince1970, since.addingTimeInterval(Fireplace.maxDuration).timeIntervalSince1970, accuracy: 1)
        // the rooms that follow the fireplace hear it as a change with origin app
        XCTAssertEqual(events.all.map(\.origin), [.app])
        XCTAssertEqual(events.all.first?.entityId, Fireplace.stateId)
    }

    func testSwitchOffHoldsAtOnce() async throws {
        try await switchFireplace(true)
        try await switchFireplace(false)

        let (_, read) = try await request(.GET, token: token)
        XCTAssertEqual(read?.isOn, false)
        XCTAssertEqual(events.all.compactMap(\.isDeviceOn), [true, false])
    }

    func testRepeatedOnKeepsTheStartAndTellsNobody() async throws {
        try await switchFireplace(true)
        let homeManager = app.homeManager
        let first = try await Fireplace.state(with: homeManager)
        let since = try XCTUnwrap(first.since)
        // the clock moves on, so a repeat that restarted the fireplace would carry a later start
        while Date() <= since { try await Task.sleep(for: .milliseconds(1)) }

        try await switchFireplace(true)

        let second = try await Fireplace.state(with: homeManager)
        XCTAssertEqual(second.since, since)
        XCTAssertEqual(events.all.count, 1)
    }
}

/// The changes the automations were told about.
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [EntityStorageItem] = []

    var all: [EntityStorageItem] { lock.withLock { items } }
    func append(_ item: EntityStorageItem) { lock.withLock { items.append(item) } }
}

struct EmptyStorage: StorageRepository {
    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem? { nil }
    func getAllCurrent() async throws -> [EntityStorageItem] { [] }
    func add(_ item: EntityStorageItem) async throws {}
    func getHistory(for entityId: EntityId, startDate: Date?, endDate: Date?, cursor: Date?, limit: Int) async throws -> [EntityStorageItem] { [] }
    func getAllEntityIds() async throws -> [EntityId] { [] }
}
struct SilentSender: NotificationSender {
    func sendNotification(title: String, message: String, id: String, category: String?) async throws {}
    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState, activityName: String, options: LiveActivityOptions) async {}
    func endAllLiveActivities(ofActivityType activityType: String) async {}
}

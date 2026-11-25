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
    private var switches: FireplaceSwitches!
    private var events: EventLog!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        app.environment.arguments = ["serve"]
        app.authToken = token
        app.authDisabled = false
        app.homeAutomationConfigService = HomeAutomationConfigService(location: Location(latitude: 52.52, longitude: 13.405),
                                                                      automations: [], persist: { _ in })
        app.starActorSystem = StarActorSystem(name: "fireplace-tests")
        switches = FireplaceSwitches()
        events = EventLog()
        // no adapter: the fireplace is the server's own state and needs none
        app.homeManager = await HomeManager(getAdapter: { nil },
                                            storageRepo: EmptyStorage(),
                                            notificationSender: SilentSender(),
                                            location: Location(latitude: 52.52, longitude: 13.405),
                                            actionLogManager: ActionLogManager(),
                                            fireplaceSwitches: switches,
                                            onFireplaceSwitch: { [events] in events?.append($0) })
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

    func testNeverSwitchedIsOff() async throws {
        let (status, state) = try await request(.GET, token: token)
        XCTAssertEqual(status, .ok)
        XCTAssertEqual(state?.isOn, false)
        XCTAssertNil(state?.since)
    }

    func testStateSaysSinceAndEnd() async throws {
        let start = Date(timeIntervalSinceNow: -3600)
        try await switches.add(FireplaceSwitch(timestamp: start, isOn: true))

        let (status, state) = try await request(.GET, token: token)

        XCTAssertEqual(status, .ok)
        XCTAssertEqual(state?.isOn, true)
        XCTAssertEqual(try XCTUnwrap(state?.since).timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(state?.endsAt).timeIntervalSince1970, start.addingTimeInterval(Fireplace.maxDuration).timeIntervalSince1970, accuracy: 1)
    }

    func testSwitchOnHoldsAtOnceIsStoredAndTellsTheAutomations() async throws {
        let (status, state) = try await request(.PUT, token: token, body: #"{"isOn":true}"#)
        XCTAssertEqual(status, .ok)
        XCTAssertEqual(state?.isOn, true)
        XCTAssertNotNil(state?.endsAt)

        let (_, read) = try await request(.GET, token: token)
        XCTAssertEqual(read?.isOn, true)
        let stored = await switches.all
        XCTAssertEqual(stored.map(\.isOn), [true])
        XCTAssertEqual(events.all.map(\.isOn), [true])
    }

    func testSwitchOffHoldsAtOnce() async throws {
        try await switches.add(FireplaceSwitch(timestamp: Date(timeIntervalSinceNow: -60), isOn: true))

        let (status, state) = try await request(.PUT, token: token, body: #"{"isOn":false}"#)
        XCTAssertEqual(status, .ok)
        XCTAssertEqual(state?.isOn, false)

        let (_, read) = try await request(.GET, token: token)
        XCTAssertEqual(read?.isOn, false)
        XCTAssertEqual(events.all.map(\.isOn), [false])
    }

    func testRepeatedOnKeepsTheStartAndTellsNobody() async throws {
        let start = Date(timeIntervalSinceNow: -600)
        try await switches.add(FireplaceSwitch(timestamp: start, isOn: true))

        let (_, state) = try await request(.PUT, token: token, body: #"{"isOn":true}"#)

        XCTAssertEqual(try XCTUnwrap(state?.since).timeIntervalSince1970, start.timeIntervalSince1970, accuracy: 1)
        let stored = await switches.all
        XCTAssertEqual(stored.count, 1)
        XCTAssertTrue(events.all.isEmpty)
    }
}

private actor FireplaceSwitches: FireplaceRepository {
    private(set) var all: [FireplaceSwitch] = []

    func add(_ fireplaceSwitch: FireplaceSwitch) async throws { all.append(fireplaceSwitch) }
    func latest() async throws -> FireplaceSwitch? { all.last }
    func switches(from startDate: Date, to endDate: Date) async throws -> [FireplaceSwitch] { all }
}

/// The switches the automations were told about.
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var switches: [FireplaceSwitch] = []

    var all: [FireplaceSwitch] { lock.withLock { switches } }
    func append(_ fireplaceSwitch: FireplaceSwitch) { lock.withLock { switches.append(fireplaceSwitch) } }
}

private struct EmptyStorage: StorageRepository {
    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem? { nil }
    func getPrevious(_ entityId: EntityId) async throws -> EntityStorageItem? { nil }
    func getAllCurrent() async throws -> [EntityStorageItem] { [] }
    func add(_ item: EntityStorageItem) async throws {}
    func getHistory(for entityId: EntityId, startDate: Date?, endDate: Date?, cursor: Date?, limit: Int) async throws -> [EntityStorageItem] { [] }
    func getAllEntityIds() async throws -> [EntityId] { [] }
}
private struct SilentSender: NotificationSender {
    func sendNotification(title: String, message: String, id: String, category: String?) async throws {}
    func clearNotification(id: String) async throws {}
    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState, activityName: String, options: LiveActivityOptions) async {}
    func endAllLiveActivities(ofActivityType activityType: String) async {}
}

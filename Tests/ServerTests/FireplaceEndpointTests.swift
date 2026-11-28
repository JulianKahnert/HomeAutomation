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
    private var storage: MemoryStorage!
    private var loop: Task<Void, Never>!

    override func setUp() async throws {
        app = try await Application.make(.testing)
        app.environment.arguments = ["serve"]
        app.authToken = token
        app.authDisabled = false
        app.homeAutomationConfigService = HomeAutomationConfigService(location: Location(latitude: 52.52, longitude: 13.405), persist: { _ in })
        app.automationService = try await makeAutomationService(automations: [])
        app.starActorSystem = StarActorSystem(name: "fireplace-tests")
        events = EventLog()
        storage = MemoryStorage()
        app.storageReader = storage
        // no adapter: the fireplace is the server's own state and needs none
        app.homeManager = await HomeManager(getAdapter: { nil },
                                            storageRepo: storage,
                                            notificationSender: SilentSender(),
                                            location: Location(latitude: 52.52, longitude: 13.405),
                                            onReportedChange: { [events, app] in
            events?.append($0)
            app?.homeEventSink.yield(.change(entity: $0))
        })
        loop = app.startEventLoop()
        try routes(app)
    }

    override func tearDown() async throws {
        loop.cancel()
        try await app.asyncShutdown()
        app = nil
    }

    private struct State: Decodable {
        let isOn: Bool
        let since: Date?
        let asksAt: Date?
        let isAsking: Bool?
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
        // the read side answers from the database, which the background queue fills
        await storage.waitForChanges(1)

        let (status, state) = try await request(.GET, token: token)
        XCTAssertEqual(status, .ok)
        XCTAssertEqual(state?.isOn, true)
        let since = try XCTUnwrap(state?.since)
        XCTAssertEqual(since.timeIntervalSince1970, before.timeIntervalSince1970, accuracy: 5)
        XCTAssertEqual(try XCTUnwrap(state?.asksAt).timeIntervalSince1970, since.addingTimeInterval(Fireplace.maxDuration).timeIntervalSince1970, accuracy: 1)
        let endsAt = since.addingTimeInterval(Fireplace.maxDuration + Fireplace.answerTimeout)
        XCTAssertEqual(try XCTUnwrap(state?.endsAt).timeIntervalSince1970, endsAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(state?.isAsking, false)
        // the rooms that follow the fireplace hear it as a change with origin app
        XCTAssertEqual(events.all.map(\.origin), [.app])
        XCTAssertEqual(events.all.first?.entityId, Fireplace.stateId)
    }

    func testSwitchOffHoldsAtOnce() async throws {
        try await switchFireplace(true)
        try await switchFireplace(false)
        await storage.waitForChanges(2)

        let (_, read) = try await request(.GET, token: token)
        XCTAssertEqual(read?.isOn, false)
        XCTAssertEqual(events.all.compactMap(\.isDeviceOn), [true, false])
    }

    @discardableResult
    private func answer(stillOn: Bool) async throws -> (HTTPStatus, State?) {
        try await request(.POST, "/heating/fireplace/answer", token: token, body: #"{"stillOn":\#(stillOn)}"#)
    }

    func testAnswerRequiresAuthentication() async throws {
        let (status, _) = try await request(.POST, "/heating/fireplace/answer", token: nil, body: #"{"stillOn":true}"#)
        XCTAssertEqual(status, .unauthorized)
    }

    func testAnswerNoSwitchesTheFireplaceOff() async throws {
        try await switchFireplace(true)
        await storage.waitForChanges(1)

        let (status, state) = try await answer(stillOn: false)
        XCTAssertEqual(status, .ok)
        XCTAssertEqual(state?.isOn, false)
        await storage.waitForChanges(2)
        XCTAssertEqual(try await Fireplace.state(from: storage), .off)
        XCTAssertEqual(events.all.last?.entityId, Fireplace.stateId)
        XCTAssertEqual(events.all.last?.origin, .app)
    }

    func testAnswerYesSetsTheNextQuestionAhead() async throws {
        try await switchFireplace(true)
        await storage.waitForChanges(1)
        let before = Date()

        let (status, state) = try await answer(stillOn: true)
        XCTAssertEqual(status, .ok)
        XCTAssertEqual(state?.isOn, true)
        XCTAssertEqual(state?.isAsking, false)
        let asksAt = before.addingTimeInterval(Fireplace.maxDuration)
        XCTAssertEqual(try XCTUnwrap(state?.asksAt).timeIntervalSince1970, asksAt.timeIntervalSince1970, accuracy: 5)
        // the fireplace stays on; the question entity changed with origin app, which FireplaceTimeout hears
        XCTAssertEqual(events.all.last?.entityId, Fireplace.questionId)
        XCTAssertEqual(events.all.last?.origin, .app)
        XCTAssertEqual(events.all.filter { $0.entityId == Fireplace.stateId }.count, 1)
    }

    func testAnswerYesWhileOffChangesNothing() async throws {
        let (status, state) = try await answer(stillOn: true)
        XCTAssertEqual(status, .ok)
        XCTAssertEqual(state?.isOn, false)
        XCTAssertTrue(events.all.isEmpty)
    }

    func testRepeatedOnKeepsTheStartAndTellsNobody() async throws {
        try await switchFireplace(true)
        await storage.waitForChanges(1)
        let first = try await Fireplace.state(from: storage)
        let since = try XCTUnwrap(first.since)
        // the clock moves on, so a repeat that restarted the fireplace would carry a later start
        while Date() <= since { try await Task.sleep(for: .milliseconds(1)) }

        try await switchFireplace(true)

        let second = try await Fireplace.state(from: storage)
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

struct SilentSender: NotificationSender {
    func sendNotification(title: String, message: String, id: String, category: String?) async throws {}
    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState, activityName: String, options: LiveActivityOptions) async {}
    func endAllLiveActivities<ContentState: Encodable & Sendable>(ofActivityType activityType: String, finalContentState: ContentState) async {}
}

//
//  WriteEventFlowTests.swift
//  HomeAutomationServer
//

import Foundation
import HAApplicationLayer
@testable import HAImplementations
@testable import HAModels
@testable import Server
import Shared
import StarActorSystem
import Synchronization
import XCTVapor

/// T27: every write enters the core as an event of the event stream, in order with the other events, and the caller
/// waits for the loop's answer.
final class WriteEventFlowTests: XCTestCase {
    var app: Application!
    private let token = "write-flow-test-token"
    private var storage: MemoryStorage!
    private var automationService: AutomationService!
    private var repository: InMemoryAutomationRepository!
    private var stream: AsyncStream<HomeInput>!
    private var loop: Task<Void, Never>?

    override func setUp() async throws {
        app = try await Application.make(.testing)
        app.environment.arguments = ["serve"]
        app.authToken = token
        app.authDisabled = false
        app.starActorSystem = StarActorSystem(name: "write-flow-tests")
        storage = MemoryStorage()
        app.storageReader = storage
        app.homeManager = await HomeManager(getAdapter: { nil },
                                            storageRepo: storage,
                                            notificationSender: SilentSender(),
                                            location: Location(latitude: 52.52, longitude: 13.405),
                                            onReportedChange: { [app] in app?.homeEventSink.yield(.change(entity: $0)) })
        repository = InMemoryAutomationRepository()
        automationService = try AutomationService(using: app.homeManager, runs: NoRuns(), automations: [Probe()], repository: repository)
        app.automationService = automationService
        let (stream, continuation) = AsyncStream.makeStream(of: HomeInput.self)
        self.stream = stream
        app.homeEventsStream = stream
        app.homeEventsContinuation = continuation
        try routes(app)
    }

    override func tearDown() async throws {
        loop?.cancel()
        try await app.asyncShutdown()
        app = nil
    }

    private func startLoop() {
        let job = HomeEventProcessingJob(gauge: app.eventLoopGauge, homeEventsStream: stream,
                                         automationService: automationService, homeManager: app.homeManager)
        loop = Task { await job.run() }
    }

    private func send(_ method: HTTPMethod, _ path: String, json: String? = nil) async throws -> HTTPStatus {
        var status: HTTPStatus = .internalServerError
        try await app.test(method, path, beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            if let json {
                req.headers.contentType = .json
                req.body = ByteBuffer(string: json)
            }
        }, afterResponse: { res async in status = res.status })
        return status
    }

    private let fireplaceBody = #"{"entityId":{"placeId":"server","name":"fireplace","characteristicType":"switcher"},"value":true}"#

    // MARK: - order

    func testAWriteIsHandledAfterTheEventsQueuedBeforeIt() async throws {
        let lamp = EntityId(placeId: "room", name: "lamp", characteristicsName: nil, characteristic: .switcher)
        let before = EntityStorageItem(entityId: lamp, isDeviceOn: true)
        // queued before the loop runs: the adapter's report, the write, a later report
        app.homeEventSink.yield(.change(entity: before))
        let answer = Mutex<Result<StateChange?, any Error>?>(nil)
        let write = WriteCommand(kind: .setState(Fireplace.stateId, .bool(true)), complete: { result in answer.withLock { $0 = result } })
        app.homeEventSink.yield(.write(write))
        app.homeEventSink.yield(.change(entity: EntityStorageItem(entityId: lamp, isDeviceOn: false)))

        startLoop()
        await storage.waitForChanges(3)

        // the stored order is the order the loop handled them in
        let order = await storage.addedIds
        XCTAssertEqual(order, [lamp, Fireplace.stateId, lamp])
        XCTAssertNotNil(answer.withLock { $0 })
    }

    // MARK: - the route answers within the timeout

    func testTheRouteAnswersWithTheNewStateWhenTheLoopRuns() async throws {
        startLoop()
        let status = try await send(.PUT, "/entities/state", json: fireplaceBody)
        XCTAssertEqual(status, .ok)
    }

    func testActivateDeactivateAndStopAnswerOk() async throws {
        startLoop()
        var status = try await send(.POST, "/config/automations/probe/deactivate")
        XCTAssertEqual(status, .ok)
        var active = await automationService.automations.first { $0.name == "probe" }?.isActive
        XCTAssertEqual(active, false)
        // stored with the new active state
        let saved = await repository.saved.first { $0.name == "probe" }?.isActive
        XCTAssertEqual(saved, false)

        status = try await send(.POST, "/config/automations/probe/activate")
        XCTAssertEqual(status, .ok)
        active = await automationService.automations.first { $0.name == "probe" }?.isActive
        XCTAssertEqual(active, true)

        status = try await send(.POST, "/config/automations/probe/stop")
        XCTAssertEqual(status, .ok)
    }

    func testDeployReplacesTheAutomationsAndAnswersTheConfig() async throws {
        startLoop()
        let dto = ConfigDTO(location: Location(latitude: 1, longitude: 2), automations: [AnyAutomation.create(from: DatabaseCleanup())])
        let body = String(decoding: try JSONEncoder().encode(dto), as: UTF8.self)

        let status = try await send(.POST, "/config?skipValidation=true", json: body)

        XCTAssertEqual(status, .ok)
        let names = await automationService.automations.map(\.name)
        XCTAssertEqual(names, ["DatabaseCleanup"])
    }

    // MARK: - the timeout

    func testABlockedLoopAnswers503AndTheCommandIsHandledLater() async throws {
        app.commandPort = EventFlowCommandPort(sink: app.homeEventSink, timeout: .milliseconds(50), unknownEntities: { _ in [] })

        // no loop is running: the write waits in the stream
        let status = try await send(.PUT, "/entities/state", json: fireplaceBody)
        XCTAssertEqual(status, .serviceUnavailable)
        let held = try await storage.getCurrent(Fireplace.stateId)
        XCTAssertNil(held)

        // the loop gets to it: the event is still handled
        startLoop()
        await storage.waitForChanges(1)
        let after = try await storage.getCurrent(Fireplace.stateId)
        XCTAssertEqual(after?.isDeviceOn, true)
    }

    // MARK: - the gauge

    func testTheGaugeCountsWritesWhileTheyWait() async throws {
        let gauge = app.eventLoopGauge
        app.homeEventSink.yield(.write(WriteCommand(kind: .stopAutomation(name: "probe"), complete: { _ in })))
        let later = Date().addingTimeInterval(120)
        XCTAssertGreaterThan(gauge.age(now: later), 100)
        XCTAssertNotNil(gauge.reportsBacklog(olderThan: 60, now: later))
    }

    // MARK: - failures and slow saves

    func testAFailingSaveAnswers500FastAndNotAfterTheTimeout() async throws {
        automationService = try AutomationService(using: app.homeManager, runs: NoRuns(), automations: [Probe()], repository: ThrowingRepository())
        startLoop()
        let status = try await send(.POST, "/config/automations/probe/activate")
        XCTAssertEqual(status, .internalServerError)
    }

    func testAStoppedLoopAnswers503ForADeployAndTheDeployRunsLater() async throws {
        app.commandPort = EventFlowCommandPort(sink: app.homeEventSink, timeout: .milliseconds(50), unknownEntities: { _ in [] })
        let dto = ConfigDTO(location: Location(latitude: 1, longitude: 2), automations: [AnyAutomation.create(from: DatabaseCleanup())])
        let body = String(decoding: try JSONEncoder().encode(dto), as: UTF8.self)

        let status = try await send(.POST, "/config?skipValidation=true", json: body)
        XCTAssertEqual(status, .serviceUnavailable)

        startLoop()
        // an event queued behind the deploy is handled after it
        let lamp = EntityId(placeId: "room", name: "lamp", characteristicsName: nil, characteristic: .switcher)
        app.homeEventSink.yield(.change(entity: EntityStorageItem(entityId: lamp, isDeviceOn: true)))
        await storage.waitForChanges(1)
        let names = await automationService.automations.map(\.name)
        XCTAssertEqual(names, ["DatabaseCleanup"])
    }

    func testASlowSaveDoesNotHoldTheLoop() async throws {
        let repository = BlockingRepository()
        automationService = try AutomationService(using: app.homeManager, runs: NoRuns(), automations: [Probe()], repository: repository)
        startLoop()

        // the activate waits for its save, which does not end
        let app = try XCTUnwrap(app)
        let token = token
        let request = Task { () -> HTTPStatus in
            var status: HTTPStatus = .internalServerError
            try await app.test(.POST, "/config/automations/probe/deactivate", beforeRequest: { req in
                req.headers.add(name: .authorization, value: "Bearer \(token)")
            }, afterResponse: { res async in status = res.status })
            return status
        }
        await repository.saveStarted.wait()

        // an event behind it is still handled by the loop
        let lamp = EntityId(placeId: "room", name: "lamp", characteristicsName: nil, characteristic: .switcher)
        app.homeEventSink.yield(.change(entity: EntityStorageItem(entityId: lamp, isDeviceOn: true)))
        await storage.waitForChanges(1)

        await repository.releaseSave.open()
        let status = try await request.value
        XCTAssertEqual(status, .ok)
    }

    func testACancelledRequestEnqueuesNoWrite() async throws {
        let gate = Signal()
        let port = app.commandPort
        let task = Task {
            // Not `wait()`: its timeout race ends at once in a cancelled task and would fail the test
            // whenever the task starts before the gate opens.
            await gate.waitIgnoringCancellation()
            try await port.stopAutomation(name: "probe")
        }
        task.cancel()
        await gate.open()
        let result = await task.result
        XCTAssertThrowsError(try result.get()) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(app.eventLoopGauge.age(now: Date().addingTimeInterval(120)), 0)
    }

    func testAWriteReleasedUnhandledAnswersDropped() {
        let answer = Mutex<Result<StateChange?, any Error>?>(nil)
        do {
            _ = WriteCommand(kind: .stopAutomation(name: "probe"), complete: { result in answer.withLock { $0 = result } })
        }
        guard case .failure(let error)? = answer.withLock({ $0 }) else { return XCTFail("no answer") }
        XCTAssertEqual(error as? CoreCommandError, .dropped)
    }

    // MARK: - stop never waits on a lane

    func testStopCancelsTheRunWhileItsLaneIsBusyChecking() async throws {
        let probe = Probe(name: "blocking", blocks: BlockingSignals())
        automationService = try AutomationService(using: app.homeManager, runs: NoRuns(), automations: [probe], repository: repository)
        startLoop()
        let signals = try XCTUnwrap(probe.blocks)

        // a run starts and waits for its cancellation
        app.homeEventSink.yield(.serverStarted)
        await signals.runStarted.wait()
        // the lane is now held inside `shouldTrigger` of a later event
        app.homeEventSink.yield(.sunrise)
        await signals.laneBlocked.wait()

        try await app.commandPort.stopAutomation(name: "blocking")

        // the stop returned although the lane has not finished; the run was cancelled
        await signals.runCancelled.wait()
        await signals.releaseLane.open()
        await automationService.waitUntilIdle()
    }
}

private struct ThrowingRepository: AutomationRepository {
    struct Failure: Error {}
    func save(_ automations: [any Automatable], location: Location?) async throws { throw Failure() }
}

/// A repository whose save starts and then waits until the test releases it.
private final class BlockingRepository: AutomationRepository {
    let saveStarted = Signal()
    let releaseSave = Signal()

    func save(_ automations: [any Automatable], location: Location?) async throws {
        await saveStarted.open()
        await releaseSave.wait()
    }
}

/// A one-shot signal: `wait` returns once `open` was called, whichever comes first.
actor Signal {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }

    /// Returns once opened; fails the test after `timeout` instead of hanging.
    func wait(timeout: Duration = .seconds(10), file: StaticString = #filePath, line: UInt = #line) async {
        guard !isOpen else { return }
        do {
            try await raceTimeout(timeout, timeoutError: { TestWaitTimeout() }) { await self.park() }
        } catch {
            XCTFail("A signal was not opened within \(timeout)", file: file, line: line)
        }
    }

    /// Returns once opened, even when the calling task is cancelled meanwhile.
    func waitIgnoringCancellation() async {
        await park()
    }

    private func park() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

final class BlockingSignals: Sendable {
    let runStarted = Signal()
    let laneBlocked = Signal()
    let releaseLane = Signal()
    let runCancelled = Signal()
}

/// Starts a run on `.serverStarted` that waits for its cancellation; holds its lane inside `shouldTrigger` on `.sunrise`.
private struct Probe: Automatable {
    var isActive = true
    var name = "probe"
    var blocks: BlockingSignals?

    init(name: String = "probe", blocks: BlockingSignals? = nil) {
        self.name = name
        self.blocks = blocks
    }

    private enum CodingKeys: String, CodingKey { case isActive, name }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        name = try container.decode(String.self, forKey: .name)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(name, forKey: .name)
    }

    func shouldTrigger(with event: HomeEvent, using homeManager: HomeManagable) async throws -> Bool {
        guard let blocks else { return false }
        switch event {
        case .serverStarted:
            return true
        case .sunrise:
            await blocks.laneBlocked.open()
            await blocks.releaseLane.wait()
            return false
        default:
            return false
        }
    }

    func execute(using homeManager: HomeManagable) async throws {
        guard let blocks else { return }
        await blocks.runStarted.open()
        do {
            try await Task.sleep(for: .seconds(3600))
        } catch {
            await blocks.runCancelled.open()
            throw error
        }
    }
}

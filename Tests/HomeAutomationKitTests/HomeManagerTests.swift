//
//  HomeManagerTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 03.08.26.
//

import Distributed
import Foundation
import HAApplicationLayer
@testable import HAImplementations
import HAModels
import Logging
import Synchronization
import Testing

private enum FakeAdapterError: Error {
    case unreachable
    /// What the adapter answers once `homed` dropped it.
    case accessDenied(String = #"Error Domain=HMErrorDomain Code=80 "Missing entitlement for API.""#)
}

private struct StorageFailure: Error {}

/// Observes what the adapter was asked to do and controls how it responds.
private actor AdapterProbe {
    private(set) var startedPerforms = 0
    private(set) var completedPerforms = 0
    private(set) var performedActions: [HomeManagableAction] = []
    /// The entities the adapter was asked to find.
    private(set) var foundEntities: [EntityId] = []

    private var failure: FakeAdapterError?
    private let performDuration: Duration?

    func setFailure(_ failure: FakeAdapterError?) {
        self.failure = failure
    }

    init(failure: FakeAdapterError? = nil, performDuration: Duration? = nil) {
        self.failure = failure
        self.performDuration = performDuration
    }

    /// Records every attempt, including the failing ones.
    func perform(_ action: HomeManagableAction) async throws {
        startedPerforms += 1
        performedActions.append(action)

        if let performDuration {
            // Deliberately not `try?`: if cancellation reached the shielded command, the sleep
            // throws and the command is recorded as not completed.
            try await Task.sleep(for: performDuration)
        }

        if let failure { throw failure }

        completedPerforms += 1
    }

    /// The thermostats the adapter lists, and the items it answers for each; a thermostat without items throws.
    var thermostats: [Thermostat] = []
    var thermostatItems: [Thermostat: [EntityStorageItem]] = [:]

    func setThermostats(_ items: [Thermostat: [EntityStorageItem]]) {
        thermostats = Array(items.keys)
        thermostatItems = items
    }

    func readThermostat(_ thermostat: Thermostat) throws -> [EntityStorageItem] {
        guard let items = thermostatItems[thermostat] else { throw FakeAdapterError.unreachable }
        return items
    }

    func find(_ entityId: EntityId) {
        foundEntities.append(entityId)
    }

    func waitForStart() async {
        while startedPerforms == 0 {
            await Task.yield()
        }
    }

    func waitForPerforms(_ count: Int, timeout: Duration = .seconds(1)) async {
        let deadline = ContinuousClock.now + timeout
        while startedPerforms < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// `MockHomeAdapter` is a `HomeManagable`, not an `EntityAdapterable`, so `HomeManager` needs its own
/// adapter double: a distributed actor on the local testing actor system.
private distributed actor FakeEntityAdapter: EntityAdapterable {
    typealias ActorSystem = LocalTestingDistributedActorSystem

    private let probe: AdapterProbe

    init(actorSystem: ActorSystem, probe: AdapterProbe) {
        self.actorSystem = actorSystem
        self.probe = probe
    }

    distributed func getAllEntitiesLive() async -> [EntityStorageItem] {
        []
    }

    distributed func findEntity(_ entity: EntityId) async throws {
        await probe.find(entity)
    }

    distributed func perform(_ action: HomeManagableAction) async throws {
        try await probe.perform(action)
    }

    distributed func trigger(scene sceneName: String) async throws {}

    distributed func listThermostats() async throws -> [Thermostat] { await probe.thermostats }

    distributed func readThermostat(_ thermostat: Thermostat) async throws -> [EntityStorageItem] {
        try await probe.readThermostat(thermostat)
    }
}

/// Keeps every log line a logger wrote, so a test can read them.
private final class RecordingLogHandler: LogHandler, @unchecked Sendable {
    struct Line: Sendable {
        let level: Logger.Level
        let message: String
        let metadata: Logger.Metadata
    }

    private let lines = Mutex<[Line]>([])
    var metadata = Logger.Metadata()
    var logLevel = Logger.Level.trace

    var recorded: [Line] { lines.withLock { $0 } }

    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    func log(event: LogEvent) {
        let merged = metadata.merging(event.metadata ?? [:]) { _, new in new }
        lines.withLock { $0.append(Line(level: event.level, message: "\(event.message)", metadata: merged)) }
    }
}

/// Polls until `condition` holds and records an issue when it does not within `timeout`.
private func eventually(timeout: Duration = .seconds(5), _ comment: Comment, sourceLocation: SourceLocation = #_sourceLocation,
                        _ condition: () async -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(2))
    }
    Issue.record("Did not happen within \(timeout): \(comment)", sourceLocation: sourceLocation)
}

struct HomeManagerTests {

    private let switchId = EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .switcher)

    /// - Parameter retryTicks: Defaults to a stream that finishes right away, so retries only happen
    ///   in the tests that drive them.
    private func makeHomeManager(probe: AdapterProbe,
                                 storageRepo: any StorageRepository = MockStorageRepository(),
                                 onReportedChange: @escaping @Sendable (EntityStorageItem) -> Void = { _ in },
                                 retryTicks: AsyncStream<Void> = AsyncStream { _ in },
                                 persistRetryDelays: [Duration] = [.zero, .zero],
                                 journal: Journal = Journal(store: InMemoryJournalStore()),
                                 logger: Logger = Logger(label: "HomeManagerTests")) async -> HomeManager {
        let adapter = FakeEntityAdapter(actorSystem: LocalTestingDistributedActorSystem(), probe: probe)
        return await HomeManager(getAdapter: { adapter },
                                 storageRepo: storageRepo,
                                 notificationSender: MockNotificationSender(),
                                 location: Location(latitude: 0, longitude: 0),
                                 journal: journal,
                                 onReportedChange: onReportedChange,
                                 retryTicks: retryTicks,
                                 persistRetryDelays: persistRetryDelays,
                                 logger: logger)
    }

    private static func setHeatingActions(_ actions: [HomeManagableAction]) -> [HomeManagableAction] {
        actions.filter { action in
            guard case .setHeating = action else { return false }
            return true
        }
    }

    // MARK: - server-owned entities

    private let holidayId = EntityId.serverOwned(name: "holiday", characteristic: .switcher)
    private let priceId = EntityId.serverOwned(name: "price", characteristic: .temperatureSensor)

    @Test("A report tells whether the state changed and a repeated value changes nothing and keeps the timestamp")
    func reportTellsWhetherItChanged() async throws {
        let homeManager = await makeHomeManager(probe: AdapterProbe())

        #expect(try await homeManager.report(holidayId, value: .bool(true)))
        let first = try await homeManager.getCurrentEntity(with: holidayId)
        try await Task.sleep(for: .milliseconds(20))

        #expect(try await homeManager.report(holidayId, value: .bool(true)) == false)
        #expect(try await homeManager.getCurrentEntity(with: holidayId).timestamp == first.timestamp)
        #expect(try await homeManager.report(holidayId, value: .bool(false)))
        #expect(try await homeManager.getCurrentEntity(with: holidayId).isDeviceOn == false)
    }

    @Test("The new state holds before the changed event is handed on")
    func stateHoldsBeforeTheEvent() async throws {
        let seen = Mutex<[EntityStorageItem]>([])
        let homeManager = await makeHomeManager(probe: AdapterProbe(), onReportedChange: { item in seen.withLock { $0.append(item) } })

        try await homeManager.report(holidayId, value: .bool(true))
        try await homeManager.report(holidayId, value: .bool(true))

        let events = seen.withLock { $0 }
        #expect(events.count == 1)
        #expect(events.first?.origin == .server)
        #expect(events.first?.isDeviceOn == true)
        #expect(try await homeManager.getCurrentEntity(with: holidayId).isDeviceOn == true)
    }

    @Test("A report carries its origin and is no sign of life for HomeKit")
    func reportIsNoSignOfLife() async throws {
        let homeManager = await makeHomeManager(probe: AdapterProbe(failure: .accessDenied()))
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true))
        await homeManager.perform(.turnOff(switchId))
        #expect(await homeManager.homeKitHealth() != .healthy)

        try await homeManager.report(holidayId, value: .bool(true), origin: .app)

        #expect(try await homeManager.getCurrentEntity(with: holidayId).origin == .app)
        #expect(await homeManager.homeKitHealth() != .healthy)
        #expect(await homeManager.lastReports().keys.contains("app"))
    }

    @Test("A server-owned state survives a restart and is stored once")
    func reportSurvivesARestart() async throws {
        let storage = RecordingStorageRepository()
        let beforeRestart = await makeHomeManager(probe: AdapterProbe(), storageRepo: storage)
        try await beforeRestart.report(priceId, value: .number(0.31))
        await storage.waitForAdds(1)

        let afterRestart = await makeHomeManager(probe: AdapterProbe(), storageRepo: storage)
        await afterRestart.loadCurrentStates(timeout: .seconds(2))

        #expect(try await afterRestart.getCurrentEntity(with: priceId).temperatureInC?.value == 0.31)
        #expect(try await afterRestart.report(priceId, value: .number(0.31)) == false)
        #expect(await storage.added.count == 1)
    }

    @Test("A failing database does not undo the state")
    func failingDatabaseKeepsTheState() async throws {
        let storage = RecordingStorageRepository(failingAdds: 100)
        let homeManager = await makeHomeManager(probe: AdapterProbe(), storageRepo: storage)

        #expect(try await homeManager.report(holidayId, value: .bool(true)))

        #expect(try await homeManager.getCurrentEntity(with: holidayId).isDeviceOn == true)
        #expect(try await homeManager.report(holidayId, value: .bool(true)) == false)
    }

    @Test("The facade reads all states of one value kind")
    func statesOfOneKind() async throws {
        let homeManager = await makeHomeManager(probe: AdapterProbe())
        let guestsId = EntityId.serverOwned(name: "guests", characteristic: .switcher)
        try await homeManager.report(holidayId, value: .bool(true))
        try await homeManager.report(guestsId, value: .bool(false))
        try await homeManager.report(priceId, value: .number(0.3))
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true))

        let switches = await homeManager.states(of: ValueKind(.switcher)).map(\.entityId)

        #expect(Set(switches) == [holidayId, guestsId, switchId])
        #expect(await homeManager.states(of: ValueKind(.temperatureSensor)).map(\.entityId) == [priceId])
    }

    @Test("A refused report throws: an entity that is not server-owned, a value that does not fit")
    func reportRefusesWhatDoesNotFit() async throws {
        let homeManager = await makeHomeManager(probe: AdapterProbe())

        await #expect(throws: ReportError.notServerOwned(switchId)) { try await homeManager.report(switchId, value: .bool(true)) }
        await #expect(throws: ReportError.valueDoesNotFit(holidayId)) { try await homeManager.report(holidayId, value: .number(1)) }
        #expect(await homeManager.states(of: ValueKind(.switcher)).isEmpty)
    }

    // MARK: - thermostats

    @Test("The home manager lists the adapter's thermostats and reads one per call")
    func readsOneThermostatPerCall() async throws {
        let probe = AdapterProbe()
        let bath = Thermostat(placeId: "bath", name: "Thermo", characteristicsName: nil)
        let valve = EntityId(placeId: "bath", name: "Thermo", characteristicsName: nil, characteristic: .valvePosition)
        await probe.setThermostats([bath: [EntityStorageItem(entityId: valve, valvePositionPercent: 40)]])
        let homeManager = await makeHomeManager(probe: probe)

        #expect(try await homeManager.listThermostats() == [bath])
        #expect(try await homeManager.readThermostat(bath).first?.valvePositionPercent == 40)
        let asleep = Thermostat(placeId: "kitchen", name: "Thermo", characteristicsName: nil)
        await #expect(throws: FakeAdapterError.self) { try await homeManager.readThermostat(asleep) }
    }

    // MARK: - command deduplication

    @Test("An executed command deduplicates an identical follow-up")
    func executedCommandIsDeduplicated() async {
        let probe = AdapterProbe()
        let homeManager = await makeHomeManager(probe: probe)

        await homeManager.perform(.turnOn(switchId))
        await homeManager.perform(.turnOn(switchId))

        #expect(await probe.startedPerforms == 1)
    }

    @Test("A failed command does not poison the dedup cache")
    func failedCommandIsNotDeduplicated() async {
        let probe = AdapterProbe(failure: .unreachable)
        let homeManager = await makeHomeManager(probe: probe)

        await homeManager.perform(.turnOn(switchId))
        await homeManager.perform(.turnOn(switchId))

        #expect(await probe.startedPerforms == 2)
    }

    // MARK: - cancellation

    @Test("A cancelled run issues no further commands")
    func cancelledRunIssuesNoCommand() async {
        let probe = AdapterProbe()
        let journal = Journal(store: InMemoryJournalStore())
        let homeManager = await makeHomeManager(probe: probe, journal: journal)

        let run = Task {
            // returns immediately once the task is cancelled
            try? await Task.sleep(for: .seconds(10))
            await homeManager.perform(.turnOn(switchId))
        }
        run.cancel()
        await run.value

        #expect(await probe.startedPerforms == 0)
        await journal.flush()
        #expect(await journal.commands(limit: nil, runId: nil).isEmpty)
    }

    @Test("Cancelling a run does not abort a command that already started")
    func startedCommandSurvivesCancellation() async {
        let probe = AdapterProbe(performDuration: .milliseconds(100))
        let homeManager = await makeHomeManager(probe: probe)

        let run = Task { await homeManager.perform(.turnOn(switchId)) }
        await probe.waitForStart()
        run.cancel()
        await run.value

        #expect(await probe.completedPerforms == 1)

        // the command counts as executed, so an identical one is still deduplicated
        await homeManager.perform(.turnOn(switchId))
        #expect(await probe.startedPerforms == 1)
    }

    // MARK: - heating writes

    private let radiator = EntityId(placeId: "Kitchen", name: "Radiator", characteristicsName: nil, characteristic: .targetTemperature)

    @Test("A radiator write with a reason lands in the journal with its value and is the last command of the radiator")
    func heatingWriteIsRecorded() async throws {
        let journal = Journal(store: InMemoryJournalStore())
        let homeManager = await makeHomeManager(probe: AdapterProbe(), journal: journal)

        await HeatingWriteContext.withReason(.plan, planTargetInC: 21) {
            await homeManager.perform(.setTargetTemperature(radiator, celsius: 21.2))
        }

        await journal.flush()
        let logged = try #require(await journal.commands(limit: nil, runId: nil).first)
        #expect(logged.reason == .plan)
        #expect(logged.planTargetInC == 21)
        let recorded = try #require(await journal.writes(placeId: "Kitchen", startDate: nil, endDate: nil).first)
        #expect(recorded.reason == .plan)
        #expect(recorded.targetTemperatureInC == 21.0)
        #expect(recorded.planTargetInC == 21)
        #expect(await homeManager.lastHeatingWrite(of: radiator)?.targetTemperatureInC == 21.0)
        #expect(await journal.lastHeatingWrites().map(\.targetTemperatureInC) == [21.0])
    }

    @Test("A command without a reason, a duplicate and a failed write are not recorded")
    func onlyExecutedWritesWithReasonAreRecorded() async {
        let journal = Journal(store: InMemoryJournalStore())
        let homeManager = await makeHomeManager(probe: AdapterProbe(), journal: journal)

        await homeManager.perform(.setTargetTemperature(radiator, celsius: 20))
        await journal.flush()
        #expect(await journal.writes(placeId: "Kitchen", startDate: nil, endDate: nil).isEmpty)

        await HeatingWriteContext.withReason(.system) {
            await homeManager.perform(.setHeating(radiator, active: true))
            await homeManager.perform(.setHeating(radiator, active: true))
        }
        await journal.flush()
        #expect(await journal.writes(placeId: "Kitchen", startDate: nil, endDate: nil).count == 1)

        let failing = Journal(store: InMemoryJournalStore())
        let failingManager = await makeHomeManager(probe: AdapterProbe(failure: .unreachable), journal: failing)
        await HeatingWriteContext.withReason(.system) {
            await failingManager.perform(.setHeating(radiator, active: true))
        }
        await failing.flush()
        #expect(await failing.writes(placeId: "Kitchen", startDate: nil, endDate: nil).isEmpty)
        #expect(await failingManager.lastHeatingWrite(of: radiator) == nil)
    }

    @Test("Every command writes one server log line with entity, action, reason and run, a cache hit included")
    func everyCommandIsOneLogLine() async {
        let handler = RecordingLogHandler()
        let homeManager = await makeHomeManager(probe: AdapterProbe(), logger: Logger(label: "test", factory: { _ in handler }))
        let runId = UUID()

        await AutomationRunContext.$runId.withValue(runId) {
            await HeatingWriteContext.withReason(.plan, planTargetInC: 19) {
                await homeManager.perform(.setTargetTemperature(radiator, celsius: 19))
            }
            await homeManager.perform(.turnOn(switchId))
            await homeManager.perform(.turnOn(switchId))
        }

        let lines = handler.recorded.filter { $0.message == "Command" }
        #expect(lines.count == 3)
        #expect(lines.allSatisfy { $0.level == .info })
        #expect(lines[0].metadata["entity"] == "\(radiator)")
        #expect(lines[0].metadata["action"] == "\(HomeManagableAction.setTargetTemperature(radiator, celsius: 19).actionName)")
        #expect(lines[0].metadata["reason"] == "plan")
        #expect(lines[0].metadata["run"] == "\(runId.uuidString)")
        #expect(lines[1].metadata["reason"] == "none")
        #expect(lines[1].metadata["entity"] == "\(switchId)")
        #expect(lines[1].metadata["cacheHit"] == "false")
        #expect(lines[2].metadata["cacheHit"] == "true")
    }

    @Test("A retried radiator write keeps its reason")
    func retryKeepsHeatingReason() async {
        let (ticks, tickContinuation) = AsyncStream<Void>.makeStream(of: Void.self)
        let journal = Journal(store: InMemoryJournalStore())
        let homeManager = await makeHomeManager(probe: AdapterProbe(failure: .unreachable), retryTicks: ticks, journal: journal)

        await HeatingWriteContext.withReason(.plan, planTargetInC: 19) {
            await homeManager.perform(.setTargetTemperature(radiator, celsius: 19))
        }
        tickContinuation.yield(())
        await eventually("the retry is journaled") {
            await journal.flush()
            return await journal.commands(limit: nil, runId: nil).count == 2
        }

        let reasons = await journal.commands(limit: nil, runId: nil).map(\.reason)
        #expect(reasons == [.plan, .plan])
    }

    // MARK: - retries

    @Test("A failing command is retried twice and then dropped")
    func failingCommandIsDroppedAfterThreeAttempts() async {
        let (ticks, tickContinuation) = AsyncStream<Void>.makeStream(of: Void.self)
        let probe = AdapterProbe(failure: .unreachable)
        let homeManager = await makeHomeManager(probe: probe, retryTicks: ticks)

        await homeManager.perform(.turnOn(switchId))
        #expect(await probe.startedPerforms == 1)

        // the retry loop consumes the ticks serially, so the attempts are ordered
        for _ in 0..<5 {
            tickContinuation.yield(())
        }
        await probe.waitForPerforms(3)

        try? await Task.sleep(for: .milliseconds(200))
        #expect(await probe.startedPerforms == 3)
    }

    @Test("Retries keep the run id, and every failed attempt is logged as failed")
    func retryKeepsRunIdAndLogsFailure() async {
        let (ticks, tickContinuation) = AsyncStream<Void>.makeStream(of: Void.self)
        let probe = AdapterProbe(failure: .unreachable)
        let journal = Journal(store: InMemoryJournalStore())
        let homeManager = await makeHomeManager(probe: probe, retryTicks: ticks, journal: journal)
        let runId = UUID()

        await AutomationRunContext.$runId.withValue(runId) {
            await homeManager.perform(.turnOn(switchId))
        }
        for _ in 0..<2 {
            tickContinuation.yield(())
        }
        await probe.waitForPerforms(3)
        await eventually("all three attempts are journaled") {
            await journal.flush()
            return await journal.commands(limit: nil, runId: runId).count == 3
        }

        let log = await journal.commands(limit: nil, runId: runId)
        #expect(log.count == 3)
        #expect(log.allSatisfy { $0.status == .failed })
    }

    @Test("Failed commands for different characteristics of one device are retried independently")
    func retriesAreKeyedPerCharacteristic() async {
        let brightnessId = EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .brightness)
        let colorTemperatureId = EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .colorTemperature)
        let (ticks, tickContinuation) = AsyncStream<Void>.makeStream(of: Void.self)
        let probe = AdapterProbe(failure: .unreachable)
        let homeManager = await makeHomeManager(probe: probe, retryTicks: ticks)

        // the characteristic is part of the EntityId, so these occupy separate retry slots
        await homeManager.perform(.setBrightness(brightnessId, 0.4))
        await homeManager.perform(.setColorTemperature(colorTemperatureId, 0.6))
        #expect(await probe.startedPerforms == 2)

        tickContinuation.yield(())
        await probe.waitForPerforms(4)
        #expect(await probe.startedPerforms == 4)
    }

    @Test("Only the newest failed command of an entity is replayed")
    func newestFailedCommandWins() async {
        let (ticks, tickContinuation) = AsyncStream<Void>.makeStream(of: Void.self)
        let probe = AdapterProbe(failure: .unreachable)
        let homeManager = await makeHomeManager(probe: probe, retryTicks: ticks)

        // both target the same switcher entity, so replaying both would be contradictory
        await homeManager.perform(.turnOn(switchId))
        await homeManager.perform(.turnOff(switchId))

        // one tick replays the one queued command once, so the third attempt is the last
        tickContinuation.yield(())
        await probe.waitForPerforms(3)

        #expect(await probe.performedActions == [.turnOn(switchId), .turnOff(switchId), .turnOff(switchId)])
    }

    @Test("A newer command for an entity drops its queued retry, so a stale command is not replayed")
    func newerCommandSupersedesRetry() async {
        let (ticks, tickContinuation) = AsyncStream<Void>.makeStream(of: Void.self)
        let probe = AdapterProbe(failure: .unreachable)
        let homeManager = await makeHomeManager(probe: probe, retryTicks: ticks)

        await homeManager.perform(.turnOff(switchId))   // fails and is queued
        await probe.setFailure(nil)
        await homeManager.perform(.turnOn(switchId))    // reaches the device

        tickContinuation.yield(())
        try? await Task.sleep(for: .milliseconds(200))

        #expect(await probe.performedActions == [.turnOff(switchId), .turnOn(switchId)])
    }

    @Test("An off that failed and waits for its retry is replaced when the window closes, so the room does not go off after the closing")
    func queuedOffIsReplacedByTheClosing() async throws {
        let (ticks, tickContinuation) = AsyncStream<Void>.makeStream(of: Void.self)
        let probe = AdapterProbe(failure: .unreachable)
        let homeManager = await makeHomeManager(probe: probe, retryTicks: ticks)
        let thermo = Radiator(query: .init(placeId: "Kitchen", name: "Thermo"))
        let window = WindowContactSensor(query: .init(placeId: "Kitchen", name: "Window"))
        let plan = HeatingPlan([.init(weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday], switchPoints: [SwitchPoint(hour: 6, targetInC: 21)])])
        let room = RoomHeating("heating-kitchen", placeId: "Kitchen", radiators: [thermo], contacts: [.window(window)],
                               configuration: HeatingConfiguration(standardPlan: plan))

        // the window has been open past its delay: the off fails and waits for its retry
        await homeManager.addEntityHistory(EntityStorageItem(entityId: window.contactSensorId, timestamp: Date().addingTimeInterval(-600), isContactOpen: true))
        try await room.execute(using: homeManager, now: Date(), sleep: { _ in })
        #expect(await homeManager.queuedRetry(of: thermo.heatingId) == .setHeating(thermo.heatingId, active: false))

        // the window closes before the retry went through
        let closed = EntityStorageItem(entityId: window.contactSensorId, timestamp: Date(), isContactOpen: false)
        await homeManager.addEntityHistory(closed)
        #expect(try await room.shouldTrigger(with: .change(entity: closed), using: homeManager))
        try await room.execute(using: homeManager, now: Date(), sleep: { _ in })

        // the adapter is back: the retries replay what the closing wrote, not the off
        await probe.setFailure(nil)
        tickContinuation.yield(())
        await eventually("both retries ran") {
            Self.setHeatingActions(await probe.performedActions).count == 3
        }
        let heating = Self.setHeatingActions(await probe.performedActions)
        #expect(heating == [.setHeating(thermo.heatingId, active: false), .setHeating(thermo.heatingId, active: true), .setHeating(thermo.heatingId, active: true)])
        #expect(await homeManager.queuedRetry(of: thermo.heatingId) == nil)
    }

    // MARK: - fireplace

    @Test("A repeated 'on' from the app keeps the start, so the two hours do not restart; the end counts with origin server")
    func fireplaceRepeatedOnKeepsStart() async throws {
        let homeManager = await makeHomeManager(probe: AdapterProbe())

        #expect(try await homeManager.report(Fireplace.stateId, value: .bool(true), origin: .app))
        let since = try #require(try await Fireplace.state(with: homeManager).since)
        try await Task.sleep(for: .milliseconds(20))
        #expect(try await homeManager.report(Fireplace.stateId, value: .bool(true), origin: .app) == false)

        #expect(try await Fireplace.state(with: homeManager) == FireplaceState(isOn: true, since: since))
        #expect(try await homeManager.report(Fireplace.stateId, value: .bool(false), origin: .server))
        #expect(try await Fireplace.state(with: homeManager) == .off)
        #expect(try await homeManager.getCurrentEntity(with: Fireplace.stateId).origin == .server)
    }

    // MARK: - entity history

    @Test("An unknown entity always counts as a change")
    func unknownEntityCountsAsChange() async {
        let homeManager = await makeHomeManager(probe: AdapterProbe())

        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true)))
    }

    @Test("A replay that only differs in timestamp is not a change")
    func replayIsNotAChange() async {
        let homeManager = await makeHomeManager(probe: AdapterProbe())
        let timestamp = Date()

        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: timestamp, isDeviceOn: true)))
        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: timestamp.addingTimeInterval(30), isDeviceOn: true)) == false)
    }

    @Test("A new value is a change")
    func newValueIsAChange() async {
        let homeManager = await makeHomeManager(probe: AdapterProbe())

        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true)))
        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: false)))
    }

    @Test("A value-identical replay is not written to storage")
    func replayIsNotPersisted() async {
        let storage = RecordingStorageRepository()
        let homeManager = await makeHomeManager(probe: AdapterProbe(), storageRepo: storage)
        let timestamp = Date()

        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: timestamp, isDeviceOn: true))
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: timestamp.addingTimeInterval(30), isDeviceOn: true))
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: timestamp.addingTimeInterval(60), isDeviceOn: false))
        // The replay never reaches the serial queue and the queue is FIFO, so once the third
        // event is saved the counts are final.
        await storage.waitForAdds(2)

        #expect(await storage.added.map(\.isDeviceOn) == [true, false])
        // the replay does not even reach the database for a lookup
        #expect(await storage.lookups == 2)
    }

    @Test("A replay hours after the last change is no change and is not stored")
    func lateReplayIsNotAChange() async {
        let storage = RecordingStorageRepository()
        let homeManager = await makeHomeManager(probe: AdapterProbe(), storageRepo: storage)
        let timestamp = Date().addingTimeInterval(-3 * 3600)

        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: timestamp, isDeviceOn: true)))
        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: Date(), isDeviceOn: true)) == false)
        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: Date(), isDeviceOn: false)))
        await storage.waitForAdds(2)

        #expect(await storage.added.map(\.isDeviceOn) == [true, false])
    }

    @Test("A replay is a sign of life for HomeKit")
    func replayCountsAsSignOfLife() async {
        let homeManager = await makeHomeManager(probe: AdapterProbe(failure: .accessDenied()))
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true))
        await homeManager.perform(.turnOff(switchId))
        #expect(await homeManager.homeKitHealth() != .healthy)

        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true)) == false)

        #expect(await homeManager.homeKitHealth() == .healthy)
    }

    @Test("A change of another origin is no sign of life for HomeKit", arguments: [Origin.server, Origin.job("valves")])
    func foreignOriginIsNoSignOfLife(origin: Origin) async {
        let homeManager = await makeHomeManager(probe: AdapterProbe(failure: .accessDenied()))
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true))
        await homeManager.perform(.turnOff(switchId))
        #expect(await homeManager.homeKitHealth() != .healthy)

        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: false, origin: origin)))

        #expect(await homeManager.homeKitHealth() != .healthy)
    }

    @Test("A replay refreshes the last report time and leaves the time of the last change")
    func replayRefreshesLastReport() async throws {
        let homeManager = await makeHomeManager(probe: AdapterProbe())
        let changed = Date(timeIntervalSinceNow: -3_600)
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: changed, isDeviceOn: true))
        let first = try #require(await homeManager.lastReport(of: switchId))

        try await Task.sleep(for: .milliseconds(20))
        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: Date(), isDeviceOn: true)) == false)

        let state = try await homeManager.getCurrentEntity(with: switchId)
        #expect(state.timestamp == changed)
        #expect(try #require(state.lastReport) > first)
    }

    @Test("After a restart the last report time is unknown until the first report")
    func lastReportUnknownAfterRestart() async throws {
        let storage = MockStorageRepository(items: [EntityStorageItem(entityId: switchId, timestamp: Date(timeIntervalSinceNow: -60), isDeviceOn: true)])
        let homeManager = await makeHomeManager(probe: AdapterProbe(), storageRepo: storage)
        await homeManager.loadCurrentStates(timeout: .seconds(5))

        #expect(try await homeManager.getCurrentEntity(with: switchId).isDeviceOn == true)
        #expect(await homeManager.lastReport(of: switchId) == nil)
        #expect(await homeManager.lastReports().isEmpty)

        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true))
        #expect(await homeManager.lastReport(of: switchId) != nil)
    }

    @Test("The last report is kept per reporting source")
    func lastReportPerSource() async {
        let homeManager = await makeHomeManager(probe: AdapterProbe())
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true))
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true, origin: .job("valves")))

        let reports = await homeManager.lastReports()
        #expect(Set(reports.keys) == ["homekit", "valves"])
    }

    @Test("A replay is dropped whatever its origin", arguments: [Origin.homekit, Origin.server, Origin.job("valves")])
    func replayIsDroppedWhateverItsOrigin(origin: Origin) async {
        let homeManager = await makeHomeManager(probe: AdapterProbe())
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true))

        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true, origin: origin)) == false)
    }

    @Test("A replay that contradicts the last command lets the command be sent again")
    func replayIsCheckedAgainstLastCommand() async {
        let probe = AdapterProbe()
        let homeManager = await makeHomeManager(probe: probe)
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true))
        await homeManager.perform(.turnOff(switchId))

        // the light is still on: the command did not take
        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true)) == false)
        await homeManager.perform(.turnOff(switchId))

        #expect(await probe.startedPerforms == 2)
    }

    @Test("The current state comes from the last report, the stored state loaded at start for an entity not yet reported")
    func currentStateComesFromLastReport() async throws {
        let stored = EntityStorageItem(entityId: switchId, timestamp: Date().addingTimeInterval(-3600), isDeviceOn: false)
        let homeManager = await makeHomeManager(probe: AdapterProbe(), storageRepo: MockStorageRepository(items: [stored]))
        await homeManager.loadCurrentStates(timeout: .seconds(2))

        #expect(try await homeManager.getCurrentEntity(with: switchId).isDeviceOn == false)

        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true))

        #expect(try await homeManager.getCurrentEntity(with: switchId).isDeviceOn == true)
    }

    @Test("A replay keeps the current state with the timestamp of the last change")
    func replayKeepsTimestampOfChange() async throws {
        let homeManager = await makeHomeManager(probe: AdapterProbe())
        let changed = Date(timeIntervalSince1970: 1_000)
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: changed, isDeviceOn: true))

        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: Date(timeIntervalSince1970: 2_000), isDeviceOn: true))

        #expect(try await homeManager.getCurrentEntity(with: switchId).timestamp == changed)
    }

    @Test("An entity reported since the start is found without asking the adapter")
    func reportedEntityIsFoundWithoutTheAdapter() async throws {
        let probe = AdapterProbe()
        let homeManager = await makeHomeManager(probe: probe)
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true))

        try await homeManager.findEntity(switchId)

        #expect(await probe.foundEntities.isEmpty)
    }

    @Test("An entity with only a stored state is looked up at the adapter, so one removed from HomeKit is noticed")
    func storedEntityIsFoundAtTheAdapter() async throws {
        let probe = AdapterProbe()
        let stored = EntityStorageItem(entityId: switchId, timestamp: Date().addingTimeInterval(-3600), isDeviceOn: true)
        let homeManager = await makeHomeManager(probe: probe, storageRepo: MockStorageRepository(items: [stored]))
        await homeManager.loadCurrentStates(timeout: .seconds(2))

        try await homeManager.findEntity(switchId)

        #expect(await probe.foundEntities == [switchId])
    }

    // MARK: - restart

    @Test("After a restart a replay of a stored value is no change and is not stored again")
    func replayAfterRestartIsNotAChange() async {
        let storage = RecordingStorageRepository()
        let lampId = EntityId(placeId: "room", name: "lamp", characteristicsName: nil, characteristic: .switcher)
        let beforeRestart = await makeHomeManager(probe: AdapterProbe(), storageRepo: storage)
        await beforeRestart.addEntityHistory(EntityStorageItem(entityId: switchId, timestamp: Date().addingTimeInterval(-3600), isDeviceOn: true))
        await storage.waitForAdds(1)

        let afterRestart = await makeHomeManager(probe: AdapterProbe(), storageRepo: storage)
        await afterRestart.loadCurrentStates(timeout: .seconds(2))

        #expect(await afterRestart.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true)) == false)
        // a later change of another entity is stored after the replay would have been
        await afterRestart.addEntityHistory(EntityStorageItem(entityId: lampId, isDeviceOn: true))
        await storage.waitForAdds(2)
        #expect(await storage.added.map(\.entityId) == [switchId, lampId])
    }

    @Test("After a restart a value that differs from the stored one is a change")
    func changedValueAfterRestartIsAChange() async {
        let stored = EntityStorageItem(entityId: switchId, timestamp: Date().addingTimeInterval(-3600), isDeviceOn: true)
        let homeManager = await makeHomeManager(probe: AdapterProbe(), storageRepo: MockStorageRepository(items: [stored]))
        await homeManager.loadCurrentStates(timeout: .seconds(2))

        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: false)))
    }

    @Test("After a restart an entity without a stored state is a change on its first report")
    func unknownEntityAfterRestartIsAChange() async {
        let stored = EntityStorageItem(entityId: switchId, timestamp: Date().addingTimeInterval(-3600), isDeviceOn: true)
        let homeManager = await makeHomeManager(probe: AdapterProbe(), storageRepo: MockStorageRepository(items: [stored]))
        await homeManager.loadCurrentStates(timeout: .seconds(2))
        let newLamp = EntityId(placeId: "room", name: "new lamp", characteristicsName: nil, characteristic: .switcher)

        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: newLamp, isDeviceOn: true)))
    }

    @Test("When the load fails, the server starts with no remembered states")
    func failedLoadStartsCold() async throws {
        let storage = RecordingStorageRepository(load: .failing)
        try await storage.add(EntityStorageItem(entityId: switchId, timestamp: Date().addingTimeInterval(-3600), isDeviceOn: true))
        let homeManager = await makeHomeManager(probe: AdapterProbe(), storageRepo: storage)
        await homeManager.loadCurrentStates(timeout: .seconds(2))

        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true)))
    }

    @Test("When the load exceeds its time limit, the server starts with no remembered states, also once it answers late",
          .timeLimit(.minutes(1)))
    func slowLoadStartsCold() async throws {
        let query = ManualSleeper()
        let timer = ManualSleeper()
        let storage = RecordingStorageRepository(load: .held(query))
        try await storage.add(EntityStorageItem(entityId: switchId, timestamp: Date().addingTimeInterval(-3600), isDeviceOn: true))
        let homeManager = await makeHomeManager(probe: AdapterProbe(), storageRepo: storage)
        let load = Task { await homeManager.loadCurrentStates(timeout: .seconds(10), sleep: { try await timer.sleep(for: $0) }) }
        _ = await query.nextSleep()

        #expect(await timer.nextSleep() == .seconds(10))
        timer.wake()
        // returns while the query still has not answered
        await load.value
        query.wake()
        await storage.waitForLateLoadAnswer()

        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true)))
    }

    @Test("A burst of events is persisted one at a time and in order")
    func burstIsPersistedSerially() async {
        let storage = RecordingStorageRepository(addDuration: .milliseconds(2))
        let homeManager = await makeHomeManager(probe: AdapterProbe(), storageRepo: storage)
        let entityIds = (0..<50).map { EntityId(placeId: "room", name: "light \($0)", characteristicsName: nil, characteristic: .switcher) }

        for entityId in entityIds {
            await homeManager.addEntityHistory(EntityStorageItem(entityId: entityId, isDeviceOn: true))
        }
        await storage.waitForAdds(entityIds.count)

        #expect(await storage.added.map(\.entityId) == entityIds)
        #expect(await storage.maxConcurrentCalls == 1)
    }

    @Test("A failed save is retried without counting the state as a change again")
    func failedSaveIsRetried() async {
        let storage = RecordingStorageRepository(failingAdds: 2)
        let homeManager = await makeHomeManager(probe: AdapterProbe(), storageRepo: storage)

        #expect(await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true)))
        await storage.waitForAdds(1)

        #expect(await storage.added.map(\.isDeviceOn) == [true])
        #expect(await storage.addAttempts == 3)
    }

    @Test("A save that keeps failing is given up and does not block later states")
    func failingSaveIsGivenUp() async {
        let storage = RecordingStorageRepository(failingAdds: 3)
        let homeManager = await makeHomeManager(probe: AdapterProbe(), storageRepo: storage)

        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true))
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: false))
        await storage.waitForAdds(1)

        #expect(await storage.added.map(\.isDeviceOn) == [false])
        #expect(await storage.addAttempts == 4)
    }

    // MARK: - HomeKit health

    @Test("A command refused with Code=80 marks HomeKit degraded until the next event")
    func accessDeniedCommandDegradesHealth() async {
        let homeManager = await makeHomeManager(probe: AdapterProbe(failure: .accessDenied()))
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true))
        #expect(await homeManager.homeKitHealth() == .healthy)

        await homeManager.perform(.turnOff(switchId))
        #expect(await homeManager.homeKitHealth() == .degraded(reason: "HomeKit refuses access (HMErrorDomain Code=80)"))

        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: false))
        #expect(await homeManager.homeKitHealth() == .healthy)
    }

    @Test("A command that fails for another reason leaves HomeKit healthy")
    func otherCommandFailureKeepsHealth() async {
        let homeManager = await makeHomeManager(probe: AdapterProbe(failure: .unreachable))
        await homeManager.addEntityHistory(EntityStorageItem(entityId: switchId, isDeviceOn: true))

        await homeManager.perform(.turnOff(switchId))

        #expect(await homeManager.homeKitHealth() == .healthy)
    }
}

/// Records what reaches the database and how many calls overlap.
private actor RecordingStorageRepository: StorageRepository {
    private(set) var added: [EntityStorageItem] = []
    private(set) var lookups = 0
    private(set) var maxConcurrentCalls = 0
    private(set) var addAttempts = 0
    private var concurrentCalls = 0
    private var failingAdds: Int
    private let addDuration: Duration?
    private let load: Load

    private var loadAnswered = false
    private var loadAnswerWaiter: CheckedContinuation<Void, Never>?

    /// How `getAllCurrent` answers.
    enum Load {
        case immediate, failing
        /// Answers once the sleeper is woken, like a slow query that ignores cancellation.
        case held(ManualSleeper)
    }

    /// - Parameter failingAdds: Number of `add` calls that throw before the first one succeeds.
    init(addDuration: Duration? = nil, failingAdds: Int = 0, load: Load = .immediate) {
        self.addDuration = addDuration
        self.failingAdds = failingAdds
        self.load = load
    }

    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem? {
        lookups += 1
        return await track { added.last { $0.entityId == entityId } }
    }

    func getPrevious(_ entityId: EntityId) async throws -> EntityStorageItem? {
        nil
    }

    func getAllCurrent() async throws -> [EntityStorageItem] {
        switch load {
        case .immediate:
            break
        case .failing:
            throw StorageFailure()
        case .held(let sleeper):
            // an unstructured task does not inherit cancellation, like a database query that ignores it
            _ = await Task { try await sleeper.sleep(for: .zero) }.result
            loadAnswered = true
            loadAnswerWaiter?.resume()
            loadAnswerWaiter = nil
        }
        return Array(Dictionary(added.map { ($0.entityId, $0) }, uniquingKeysWith: { _, newer in newer }).values)
    }

    /// Waits until a held `getAllCurrent` answered.
    func waitForLateLoadAnswer() async {
        guard !loadAnswered else { return }
        await withCheckedContinuation { loadAnswerWaiter = $0 }
    }

    func add(_ item: EntityStorageItem) async throws {
        addAttempts += 1
        if failingAdds > 0 {
            failingAdds -= 1
            throw StorageFailure()
        }
        await track {
            if let addDuration {
                try? await Task.sleep(for: addDuration)
            }
            added.append(item)
        }
    }

    func getHistory(for entityId: EntityId, startDate: Date?, endDate: Date?, cursor: Date?, limit: Int) async throws -> [EntityStorageItem] {
        []
    }

    func getAllEntityIds() async throws -> [EntityId] {
        []
    }

    func waitForAdds(_ count: Int, timeout: Duration = .seconds(30), sourceLocation: SourceLocation = #_sourceLocation) async {
        let deadline = ContinuousClock.now + timeout
        while added.count < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        if added.count < count {
            Issue.record("Expected \(count) stored items within \(timeout), saw \(added.count)", sourceLocation: sourceLocation)
        }
    }

    /// The actor is reentrant across the `await` in `body`, so overlapping calls are counted.
    private func track<T>(_ body: () async -> T) async -> T {
        concurrentCalls += 1
        maxConcurrentCalls = max(maxConcurrentCalls, concurrentCalls)
        defer { concurrentCalls -= 1 }
        return await body()
    }
}

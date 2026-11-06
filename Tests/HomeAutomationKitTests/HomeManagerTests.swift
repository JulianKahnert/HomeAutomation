//
//  HomeManagerTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 03.08.26.
//

import Distributed
import Foundation
import HAApplicationLayer
import HAModels
import Testing

private enum FakeAdapterError: Error {
    case unreachable
}

/// Observes what the adapter was asked to do and controls how it responds.
private actor AdapterProbe {
    private(set) var startedPerforms = 0
    private(set) var completedPerforms = 0
    private(set) var performedActions: [HomeManagableAction] = []

    private let failure: FakeAdapterError?
    private let performDuration: Duration?

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

    distributed func findEntity(_ entity: EntityId) async throws {}

    distributed func perform(_ action: HomeManagableAction) async throws {
        try await probe.perform(action)
    }

    distributed func trigger(scene sceneName: String) async throws {}
}

struct HomeManagerTests {

    private let switchId = EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .switcher)

    /// - Parameter retryTicks: Defaults to a stream that finishes right away, so retries only happen
    ///   in the tests that drive them.
    private func makeHomeManager(probe: AdapterProbe,
                                 storageRepo: any StorageRepository = MockStorageRepository(),
                                 retryTicks: AsyncStream<Void> = AsyncStream { _ in }) async -> HomeManager {
        let adapter = FakeEntityAdapter(actorSystem: LocalTestingDistributedActorSystem(), probe: probe)
        return await HomeManager(getAdapter: { adapter },
                                 storageRepo: storageRepo,
                                 notificationSender: MockNotificationSender(),
                                 location: Location(latitude: 0, longitude: 0),
                                 actionLogManager: ActionLogManager(),
                                 retryTicks: retryTicks)
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
        let homeManager = await makeHomeManager(probe: probe)

        let run = Task {
            // returns immediately once the task is cancelled
            try? await Task.sleep(for: .seconds(10))
            await homeManager.perform(.turnOn(switchId))
        }
        run.cancel()
        await run.value

        #expect(await probe.startedPerforms == 0)
        #expect(await homeManager.getActionLog(limit: nil, runId: nil).isEmpty)
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
        let homeManager = await makeHomeManager(probe: probe, retryTicks: ticks)
        let runId = UUID()

        await AutomationRunContext.$runId.withValue(runId) {
            await homeManager.perform(.turnOn(switchId))
        }
        for _ in 0..<2 {
            tickContinuation.yield(())
        }
        await probe.waitForPerforms(3)
        try? await Task.sleep(for: .milliseconds(200))

        let log = await homeManager.getActionLog(limit: nil, runId: runId)
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

        tickContinuation.yield(())
        await probe.waitForPerforms(3)
        try? await Task.sleep(for: .milliseconds(200))

        #expect(await probe.performedActions == [.turnOn(switchId), .turnOff(switchId), .turnOff(switchId)])
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
        await storage.waitForAdds(2)

        try? await Task.sleep(for: .milliseconds(100))
        #expect(await storage.added.map(\.isDeviceOn) == [true, false])
        // the replay does not even reach the database for a lookup
        #expect(await storage.lookups == 2)
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
}

/// Records what reaches the database and how many calls overlap.
private actor RecordingStorageRepository: StorageRepository {
    private(set) var added: [EntityStorageItem] = []
    private(set) var lookups = 0
    private(set) var maxConcurrentCalls = 0
    private var concurrentCalls = 0
    private let addDuration: Duration?

    init(addDuration: Duration? = nil) {
        self.addDuration = addDuration
    }

    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem? {
        lookups += 1
        return await track { added.last { $0.entityId == entityId } }
    }

    func getPrevious(_ entityId: EntityId) async throws -> EntityStorageItem? {
        nil
    }

    func add(_ item: EntityStorageItem) async throws {
        await track {
            if let addDuration {
                try? await Task.sleep(for: addDuration)
            }
            added.append(item)
        }
    }

    func deleteEntries(olderThan date: Date) async throws {}

    func getHistory(for entityId: EntityId, startDate: Date?, endDate: Date?, cursor: Date?, limit: Int) async throws -> [EntityStorageItem] {
        []
    }

    func getAllEntityIds() async throws -> [EntityId] {
        []
    }

    func waitForAdds(_ count: Int, timeout: Duration = .seconds(2)) async {
        let deadline = ContinuousClock.now + timeout
        while added.count < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
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

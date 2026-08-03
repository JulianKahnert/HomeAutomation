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
    private func makeHomeManager(probe: AdapterProbe, retryTicks: AsyncStream<Void> = AsyncStream { _ in }) async -> HomeManager {
        let adapter = FakeEntityAdapter(actorSystem: LocalTestingDistributedActorSystem(), probe: probe)
        return await HomeManager(getAdapter: { adapter },
                                 storageRepo: MockStorageRepository(),
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
        #expect(await homeManager.getActionLog(limit: nil).isEmpty)
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
}

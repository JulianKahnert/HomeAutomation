//
//  AutomationServiceTests.swift
//  HomeAutomationKit
//

import Foundation
import HAApplicationLayer
import HAImplementations
import HAModels
import Synchronization
import Testing

/// Triggers on every event; `execute` behaves according to `mode`.
private struct TestAutomation: Automatable {
    enum Mode: Codable { case complete, fail, waitForCancellation, swallowCancellationOnce }
    /// Tells the first `execute` of a `swallowCancellationOnce` automation from the later ones.
    final class FirstRun: Sendable {
        private let isFirst = Mutex(true)
        func take() -> Bool { isFirst.withLock { defer { $0 = false }; return $0 } }
    }
    struct Failure: Error {}

    var isActive = true
    let name: String
    let mode: Mode
    var recordsRuns = true
    var lanePolicy = LanePolicy.supersede
    var summaryDetail: String?
    /// Receives the run id seen inside `execute`; not part of the config.
    var onExecute: (@Sendable (UUID?) -> Void)?
    var firstRun = FirstRun()

    enum CodingKeys: CodingKey { case isActive, name, mode, recordsRuns, summaryDetail }

    func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool { true }

    func triggerSummary(for event: HomeEvent, using hm: HomeManagable) async -> String? { summaryDetail }

    func execute(using hm: HomeManagable) async throws {
        onExecute?(AutomationRunContext.runId)
        switch mode {
        case .complete:
            return
        case .fail:
            throw Failure()
        case .waitForCancellation:
            try await Task.sleep(for: .seconds(3600))
        case .swallowCancellationOnce:
            if firstRun.take() {
                // The run ends normally although it was told to stop.
                try? await Task.sleep(for: .seconds(3600))
            } else {
                try await Task.sleep(for: .seconds(3600))
            }
        }
    }
}

@HomeManagerActor
struct AutomationServiceTests {
    let repository = InMemoryAutomationRunRepository()
    let homeManager = MockHomeAdapter()

    private func makeService(_ automation: TestAutomation) throws -> AutomationService {
        try AutomationService(using: homeManager, runs: repository, automations: [automation])
    }

    @Test func deployKeepsTheActiveStateOfKnownAutomationsAndStoresThem() async throws {
        let store = InMemoryAutomationRepository()
        var known = TestAutomation(name: "known", mode: .complete)
        known.isActive = false
        let service = try AutomationService(using: homeManager, runs: repository, automations: [known], repository: store)

        try await service.deploy([TestAutomation(name: "known", mode: .complete), TestAutomation(name: "new", mode: .complete)])

        #expect(await service.automations.map(\.isActive) == [false, true])
        #expect(await store.saved.map(\.name) == ["known", "new"])
    }

    @Test func switchingAnAutomationStoresItsActiveState() async throws {
        let store = InMemoryAutomationRepository()
        let service = try AutomationService(using: homeManager, runs: repository, automations: [TestAutomation(name: "a", mode: .complete)], repository: store)

        try await service.setAutomationActive(with: "a", to: false)

        #expect(await service.automations.map(\.isActive) == [false])
        #expect(await store.saved.map(\.isActive) == [false])
    }

    @Test func saveOrderFollowsTheOrderOfTheChanges() async throws {
        let store = GatedAutomationRepository()
        let service = try AutomationService(using: homeManager, runs: repository, automations: [TestAutomation(name: "a", mode: .complete)], repository: store)

        let disable = Task { try await service.setAutomationActive(with: "a", to: false) }
        await store.waitUntilFirstSaveStarted()
        let enable = Task { try await service.setAutomationActive(with: "a", to: true) }
        // the second change reaches the service while the first save is blocked
        while await service.automations.map(\.isActive) != [true] { await Task.yield() }
        await store.openGate()
        try await disable.value
        try await enable.value

        // the newer snapshot is written last, so the stored state is the one the service holds
        #expect(await store.written.map { $0.map(\.isActive) } == [[false], [true]])
    }

    @Test func aDeactivatedAutomationDoesNotRun() async throws {
        let service = try makeService(TestAutomation(name: "a", mode: .complete))
        try await service.setAutomationActive(with: "a", to: false)

        await service.trigger(with: .sunrise)

        #expect(await service.getActiveAutomationNames().isEmpty)
        #expect(await repository.runs.isEmpty)
    }

    @Test func completedRunRecordsTriggerAndEnd() async throws {
        let service = try makeService(TestAutomation(name: "a", mode: .complete))

        await service.trigger(with: .sunrise)

        let run = try #require(await repository.nextFinishedRun())
        #expect(run.automationName == "a")
        #expect(run.outcome == .completed)
        #expect(run.trigger == AutomationTrigger(kind: .sunrise, entityId: nil, summary: "Sunrise"))
        #expect(run.endedAt != nil)
    }

    @Test func secondTriggerSupersedesTheRunningRun() async throws {
        let service = try makeService(TestAutomation(name: "a", mode: .waitForCancellation))

        await service.trigger(with: .sunrise)
        await service.trigger(with: .sunset)

        let run = try #require(await repository.nextFinishedRun())
        #expect(run.trigger.kind == .sunrise)
        #expect(run.outcome == .superseded)
        await service.stopAutomation(with: "a")
    }

    @Test func aTriggerDoesNotCutARunOfAnAutomationThatDoesNotSupersede() async throws {
        var automation = TestAutomation(name: "a", mode: .waitForCancellation)
        automation.lanePolicy = .skipWhileRunning
        let service = try makeService(automation)

        await service.trigger(with: .sunrise)
        await service.trigger(with: .sunset)
        await service.stopAutomation(with: "a")

        let run = try #require(await repository.nextFinishedRun())
        #expect(run.trigger.kind == .sunrise)
        #expect(run.outcome == .stopped)
        #expect(await repository.runs.count == 1)
    }

    @Test func builtInsJoinTheConfigAndKeepTheirActiveState() async throws {
        let service = try AutomationService(using: homeManager, runs: repository,
                                            automations: [TestAutomation(name: "a", mode: .complete)],
                                            builtIns: [DatabaseCleanup()])
        #expect(await service.automations.map(\.name) == ["a", DatabaseCleanup.defaultName])

        try await service.setAutomationActive(with: DatabaseCleanup.defaultName, to: false)
        try await service.deploy([TestAutomation(name: "b", mode: .complete)])

        #expect(await service.automations.map(\.name) == ["b", DatabaseCleanup.defaultName])
        #expect(await service.automations.map(\.isActive) == [true, false])
    }

    @Test func stopViaServiceEndsTheRunAsStopped() async throws {
        let service = try makeService(TestAutomation(name: "a", mode: .waitForCancellation))

        await service.trigger(with: .sunrise)
        await service.stopAutomation(with: "a")

        let run = try #require(await repository.nextFinishedRun())
        #expect(run.outcome == .stopped)
    }

    @Test func aStopThatTheRunSwallowsDoesNotLabelALaterSupersededRunAsStopped() async throws {
        let service = try makeService(TestAutomation(name: "a", mode: .swallowCancellationOnce))

        await service.trigger(with: .sunrise)
        await service.waitUntilIdle()
        await service.stopAutomation(with: "a")
        let first = try #require(await repository.nextFinishedRun())
        #expect(first.outcome == .completed)

        await service.trigger(with: .sunset)
        await service.waitUntilIdle()
        await service.trigger(with: .sunrise)

        let second = try #require(await repository.nextFinishedRun())
        #expect(second.outcome == .superseded)
        await service.stopAutomation(with: "a")
    }

    @Test func throwingExecuteEndsTheRunAsFailed() async throws {
        let service = try makeService(TestAutomation(name: "a", mode: .fail))

        await service.trigger(with: .sunrise)

        let run = try #require(await repository.nextFinishedRun())
        #expect(run.outcome == .failed)
        #expect(run.errorDescription == "Failure()")
    }

    @Test func automationWithoutRecordsRunsCreatesNoRun() async throws {
        let (executed, continuation) = AsyncStream.makeStream(of: UUID?.self)
        let service = try makeService(TestAutomation(name: "a", mode: .complete, recordsRuns: false, onExecute: { continuation.yield($0) }))

        await service.trigger(with: .sunrise)

        var iterator = executed.makeAsyncIterator()
        let runId = await iterator.next()
        #expect(runId == .some(nil))
        #expect(await repository.runs.isEmpty)
    }

    @Test func triggerSummaryOfTheAutomationIsAppended() async throws {
        let service = try makeService(TestAutomation(name: "a", mode: .complete, summaryDetail: "at 3 lx"))

        await service.trigger(with: .sunset)

        let run = try #require(await repository.nextFinishedRun())
        #expect(run.trigger.summary == "Sunset · at 3 lx")
    }

    /// The time from "motion detected" to the first command must not depend on the database.
    @Test func executeStartsWhileTheRunIsStillBeingPersisted() async throws {
        let (executed, continuation) = AsyncStream.makeStream(of: UUID?.self)
        await repository.stallAdds()
        let service = try makeService(TestAutomation(name: "a", mode: .complete, onExecute: { continuation.yield($0) }))

        let trigger = Task { await service.trigger(with: .sunrise) }
        let runId = await withTaskGroup(of: UUID?.self) { group in
            group.addTask {
                var iterator = executed.makeAsyncIterator()
                return await iterator.next().flatMap { $0 }
            }
            group.addTask {
                // The adds stay stalled until released below, so this timeout only bounds a failing
                // run; it is generous because a loaded CI runner can pause the process for seconds.
                try? await Task.sleep(for: .seconds(30))
                return nil
            }
            let first = await group.next()
            group.cancelAll()
            return first.flatMap { $0 }
        }

        #expect(runId != nil, "execute did not run while the insert was pending")
        await repository.releaseAdds()
        await trigger.value
    }

    @Test func executeSeesTheRunIdAsTaskLocal() async throws {
        let (executed, continuation) = AsyncStream.makeStream(of: UUID?.self)
        let service = try makeService(TestAutomation(name: "a", mode: .complete, onExecute: { continuation.yield($0) }))

        await service.trigger(with: .sunrise)

        var iterator = executed.makeAsyncIterator()
        let runId = try #require(await iterator.next())
        let run = try #require(await repository.nextFinishedRun())
        #expect(runId == run.id)
    }
}

/// Blocks its first save until `openGate()`; records every snapshot in the order it was written.
private actor GatedAutomationRepository: AutomationRepository {
    private(set) var written: [[any Automatable]] = []
    private var started = false
    private var gateIsOpen = false
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    func waitUntilFirstSaveStarted() async {
        if started { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func openGate() {
        gateIsOpen = true
        gateWaiters.forEach { $0.resume() }
        gateWaiters = []
    }

    func save(_ automations: [any Automatable], location: Location?) async throws {
        let isFirst = !started
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters = []
        if isFirst, !gateIsOpen {
            await withCheckedContinuation { gateWaiters.append($0) }
        }
        written.append(automations)
    }
}

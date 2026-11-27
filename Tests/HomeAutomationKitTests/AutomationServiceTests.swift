//
//  AutomationServiceTests.swift
//  HomeAutomationKit
//

import Foundation
import HAApplicationLayer
import HAImplementations
import HAModels
import Testing

/// Triggers on every event; `execute` behaves according to `mode`.
private struct TestAutomation: Automatable {
    enum Mode: Codable { case complete, fail, waitForCancellation }
    struct Failure: Error {}

    var isActive = true
    let name: String
    let mode: Mode
    var recordsRuns = true
    var supersedesRunningRun = true
    var summaryDetail: String?
    var triggerEntityIds: Set<EntityId> { [] }
    /// Receives the run id seen inside `execute`; not part of the config.
    var onExecute: (@Sendable (UUID?) -> Void)?

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
        automation.supersedesRunningRun = false
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

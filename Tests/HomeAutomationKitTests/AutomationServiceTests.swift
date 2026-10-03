//
//  AutomationServiceTests.swift
//  HomeAutomationKit
//

import Foundation
import HAApplicationLayer
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
        try AutomationService(using: homeManager, runs: repository, getAutomations: { @Sendable in [automation] })
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

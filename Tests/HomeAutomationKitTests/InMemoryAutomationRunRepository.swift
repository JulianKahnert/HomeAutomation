//
//  InMemoryAutomationRunRepository.swift
//  HomeAutomationKit
//

import Foundation
import HAModels

actor InMemoryAutomationRunRepository: AutomationRunRepository {
    private(set) var runs: [UUID: AutomationRun] = [:]
    private let finished = AsyncStream.makeStream(of: AutomationRun.self)

    /// Waits for the next run that `finish` is called for.
    func nextFinishedRun() async -> AutomationRun? {
        var iterator = finished.stream.makeAsyncIterator()
        return await iterator.next()
    }

    func add(_ run: AutomationRun) {
        runs[run.id] = run
    }

    func finish(_ id: UUID, outcome: AutomationRun.Outcome, endedAt: Date, errorDescription: String?) {
        runs[id]?.outcome = outcome
        runs[id]?.endedAt = endedAt
        runs[id]?.errorDescription = errorDescription
        if let run = runs[id] {
            finished.continuation.yield(run)
        }
    }

    func runs(for automationName: String, startDate: Date?, endDate: Date?, limit: Int) -> [AutomationRun] {
        Array(runs.values.filter { $0.automationName == automationName }.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    func latestRuns(since date: Date, limit: Int) -> [AutomationRun] {
        Array(runs.values.filter { $0.startedAt >= date }.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    func latestRunPerAutomation() -> [String: AutomationRun] {
        Dictionary(runs.values.map { ($0.automationName, $0) }) { lhs, rhs in lhs.startedAt > rhs.startedAt ? lhs : rhs }
    }

    func markRunningAsInterrupted() {
        for (id, run) in runs where run.outcome == .running {
            runs[id]?.outcome = .interrupted
        }
    }

    func deleteRuns(olderThan date: Date) {
        runs = runs.filter { $0.value.startedAt >= date }
    }
}

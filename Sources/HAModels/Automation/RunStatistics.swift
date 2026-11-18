//
//  RunStatistics.swift
//  HAModels
//

import Foundation

/// Counts over `AutomationRun`s for the run statistics charts.
public enum RunStatistics {
    public static func perDay(_ runs: [AutomationRun], days: [Date], calendar: Calendar) -> [(day: Date, count: Int)] {
        DailyTotals.countsPerDay(runs.map(\.startedAt), days: days, calendar: calendar)
    }

    /// Grouped by the triggering entity, else by the summary's first part (before " · "); most frequent first.
    public static func byTrigger(_ runs: [AutomationRun]) -> [(trigger: String, count: Int)] {
        let groups = Dictionary(grouping: runs) { run in
            run.trigger.entityId?.name ?? String(run.trigger.summary.split(separator: " · ").first ?? "")
        }
        return groups
            .map { ($0.key, $0.value.count) }
            .sorted { ($1.1, $0.0) < ($0.1, $1.0) }
    }

    public static func byOutcome(_ runs: [AutomationRun]) -> [AutomationRun.Outcome: Int] {
        runs.reduce(into: [:]) { $0[$1.outcome, default: 0] += 1 }
    }
}

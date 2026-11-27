//
//  LaneBacklogJob.swift
//  HomeAutomationServer
//

import Foundation
import HAApplicationLayer

/// Logs one critical message naming each automation whose lane holds an event older than ``limit``.
struct LaneBacklogJob: ScheduledJob {
    static let limit: TimeInterval = 60

    let automationService: AutomationService
    var name: String { "laneBacklog" }
    var cadence: Duration { .seconds(60) }

    func run(plannedAt: Date) async throws {
        await automationService.reportBacklogs(olderThan: Self.limit)
    }
}

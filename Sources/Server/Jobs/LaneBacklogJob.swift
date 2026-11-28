//
//  LaneBacklogJob.swift
//  HomeAutomationServer
//

import Foundation
import HAApplicationLayer
import Shared

/// Logs one critical message naming each automation whose lane holds an event older than ``limit``, and one when the
/// event loop's backlog is older than that.
struct LaneBacklogJob: ScheduledJob, Log {
    static let limit: TimeInterval = 60

    let automationService: AutomationService
    let gauge: EventLoopGauge
    var name: String { "laneBacklog" }
    var cadence: Duration { .seconds(60) }

    func run(plannedAt: Date) async throws {
        await automationService.reportBacklogs(olderThan: Self.limit)
        if let age = gauge.reportsBacklog(olderThan: Self.limit) {
            log.critical("Event loop is backed up", metadata: ["ageSeconds": "\(Int(age))"])
        }
    }
}

//
//  LogCleanupJob.swift
//  HomeAutomationServer
//

import Foundation
import Logging
import Shared

struct LogCleanupJob: Job, Log {
    private static let retentionDays = 7
    private static let cleanupInterval: Duration = .hours(24)

    func run() async {
        log.info("Starting LogCleanupJob - will run every 24 hours")

        await performCleanup()

        for await _ in Timer.publish(every: Self.cleanupInterval) {
            await performCleanup()
        }
    }

    private func performCleanup() async {
        let cutoff = Date().addingTimeInterval(-Double(Self.retentionDays) * 86400)
        log.info("Running log cleanup - deleting files older than \(Self.retentionDays) days (before \(cutoff))")
        await LogStore.shared.deleteEntries(olderThan: cutoff)
        log.info("Log cleanup completed")
    }
}

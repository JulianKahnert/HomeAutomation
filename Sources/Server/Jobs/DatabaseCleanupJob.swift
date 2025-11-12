//
//  DatabaseCleanupJob.swift
//  HomeAutomationServer
//
//  Created by Claude on 11.11.25.
//

import Foundation
import HAApplicationLayer
import HAModels
import Logging
import Shared

struct DatabaseCleanupJob: Job, Log {
    private static let retentionDays = 90
    private static let cleanupInterval: Duration = .hours(24) // Run once per day

    let homeManager: any HomeManagable

    func run() async {
        log.info("Starting DatabaseCleanupJob - will run every 24 hours")

        // Run initial cleanup immediately
        await performCleanup()

        // Schedule periodic cleanup every 24 hours
        for await _ in Timer.publish(every: Self.cleanupInterval) {
            await performCleanup()
        }
    }

    private func performCleanup() async {
        do {
            let cutoffDate = Date().addingTimeInterval(-1 * Duration.days(Self.retentionDays).timeInterval)
            log.info("Running database cleanup - deleting entries older than \(Self.retentionDays) days (before \(cutoffDate))")

            try await homeManager.deleteStorageEntries(olderThan: cutoffDate)

            log.info("Database cleanup completed successfully")
        } catch {
            log.error("Database cleanup failed: \(error)")
        }
    }
}

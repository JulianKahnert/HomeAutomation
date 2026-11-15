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

/// Once a day: deletes raw entity rows past their type's retention in ``StoragePolicy``, old
/// automation runs, and warns about entities that store too many rows.
///
/// `weatherSnapshots` are deliberately not touched here or by any other job: they are kept
/// indefinitely for now.
struct DatabaseCleanupJob: Job, Log {
    private static let runRetentionDays = 30
    private static let cleanupInterval: Duration = .hours(24) // Run once per day

    let entities: any EntityRetentionStore
    let automationRuns: any AutomationRunRepository
    let noisyEntityWarner: NoisyEntityWarner

    func run() async {
        log.info("Starting DatabaseCleanupJob - will run every 24 hours")

        // Run initial cleanup immediately
        await performCleanup()

        // Schedule periodic cleanup every 24 hours
        for await _ in Timer.publish(every: Self.cleanupInterval) {
            await performCleanup()
        }
    }

    func performCleanup(now: Date = Date()) async {
        do {
            for (type, cutoff) in StoragePolicy.cleanupCutoffs(now: now) {
                log.info("Deleting \(type.rawValue) entries before \(cutoff)")
                try await entities.deleteEntries(ofType: type, olderThan: cutoff)
            }
            try await automationRuns.deleteRuns(olderThan: now.addingTimeInterval(-1 * Duration.days(Self.runRetentionDays).timeInterval))
            log.info("Database cleanup completed successfully")
        } catch {
            log.error("Database cleanup failed: \(error)")
        }

        do {
            try await noisyEntityWarner.check(entities, now: now)
        } catch {
            log.error("Noisy entity check failed: \(error)")
        }
    }
}

/// Pushes a warning when an entity stored more than ``StoragePolicy/noisyEntityRowsPerDay`` rows in
/// the last 24 hours, so a noisy sensor gets a dead band before it fills the database (CO₂ stored
/// 2,300 rows a day). At most once per entity a day; a server restart resets that memory, and the
/// stable push id then replaces the earlier notification instead of adding one.
actor NoisyEntityWarner: Log {
    private let notificationSender: any NotificationSender
    private var lastWarning: [String: Date] = [:]

    init(notificationSender: any NotificationSender) {
        self.notificationSender = notificationSender
    }

    func check(_ entities: any EntityRetentionStore, now: Date) async throws {
        let day = Duration.days(1).timeInterval
        let noisy = try await entities.entitiesWithRowCount(above: StoragePolicy.noisyEntityRowsPerDay, since: now.addingTimeInterval(-day))
        for entity in noisy {
            let key = "\(entity.placeId)|\(entity.serviceName)|\(entity.characteristicType)"
            if let last = lastWarning[key], now.timeIntervalSince(last) < day {
                continue
            }
            lastWarning[key] = now
            log.warning("Noisy entity \(key): \(entity.rows) rows in 24 h")
            do {
                try await notificationSender.sendNotification(
                    title: "Noisy sensor: \(entity.serviceName)",
                    message: "\(entity.placeId) / \(entity.serviceName) (\(entity.characteristicType)) stored \(entity.rows) rows in 24 h, "
                        + "more than \(StoragePolicy.noisyEntityRowsPerDay). Consider a write dead band in StoragePolicy.",
                    id: "storage-noise-\(key)"
                )
            } catch {
                log.warning("Failed to send noisy entity warning: \(error)")
            }
        }
    }
}

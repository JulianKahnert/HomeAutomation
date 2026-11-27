//
//  DatabaseStorageUpkeep.swift
//  HomeAutomationServer
//

import Foundation
import HAApplicationLayer
import HAModels
import Logging
import Shared

/// The server's database upkeep behind ``StorageUpkeepStep``; the `DatabaseCleanup` automation reaches it
/// through the HomeManager facade.
///
/// - `cleanup`: deletes raw entity rows past their type's retention in ``StoragePolicy`` and warns about
///   entities that store too many rows. Heating writes are deliberately kept for good: the rows are small and
///   SQL queries over the long term are the point of recording them. `weatherHours` are kept
///   indefinitely for now.
/// - `rollup`: condenses the raw rows of every type whose ``StoragePolicy`` has an hourly rollup (lux, CO₂)
///   once they pass their raw retention, into `entityHourlyAggregates`, and deletes them.
/// - `journal`: deletes journal entries (runs, commands, pushes) older than 30 days.
struct DatabaseStorageUpkeep: StorageUpkeep, Log {
    static let journalRetentionDays = 30

    let entities: any EntityRetentionStore
    let journal: Journal
    let noisyEntityWarner: NoisyEntityWarner

    func perform(_ step: StorageUpkeepStep, now: Date) async throws {
        switch step {
        case .cleanup:
            await cleanUp(now: now)
        case .rollup:
            await rollUp(now: now)
        case .journal:
            try await journal.deleteEntries(olderThan: now.addingTimeInterval(-1 * Duration.days(Self.journalRetentionDays).timeInterval))
        }
    }

    private func cleanUp(now: Date) async {
        do {
            for (type, cutoff) in StoragePolicy.cleanupCutoffs(now: now) {
                log.info("Deleting \(type.rawValue) entries before \(cutoff)")
                try await entities.deleteEntries(ofType: type, olderThan: cutoff)
            }
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

    private func rollUp(now: Date) async {
        for target in StoragePolicy.rollupCutoffs(now: now) {
            do {
                try await entities.rollUpHourly(type: target.type, validRange: target.validRange, olderThan: target.before)
            } catch {
                log.error("Hourly rollup of \(target.type.rawValue) failed: \(error)")
            }
        }
    }
}

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
/// - `journal`: deletes journal entries (runs, commands, pushes) older than 30 days, except the radiator
///   commands with a heating reason (plan, window, fireplace, system): like the heating writes of the entity
///   rows they are kept for good.
struct DatabaseStorageUpkeep: StorageUpkeep, Log {
    static let journalRetentionDays = 30

    let entities: any EntityRetentionStore
    let journal: Journal
    let noisyEntityWarner: NoisyEntityWarner

    func perform(_ step: StorageUpkeepStep, now: Date) async throws {
        switch step {
        case .cleanup:
            try await cleanUp(now: now)
        case .rollup:
            try await rollUp(now: now)
        case .journal:
            try await journal.deleteEntries(olderThan: now.addingTimeInterval(-1 * Duration.days(Self.journalRetentionDays).timeInterval))
        }
    }

    private func cleanUp(now: Date) async throws {
        try await attempt("Database cleanup") {
            for (type, cutoff) in StoragePolicy.cleanupCutoffs(now: now) {
                log.info("Deleting entries past their retention", metadata: ["type": "\(type.rawValue)", "before": "\(cutoff)"])
                try await entities.deleteEntries(ofType: type, olderThan: cutoff)
            }
            log.info("Database cleanup completed successfully")
        }
        try await attempt("Noisy entity check") {
            try await noisyEntityWarner.check(entities, now: now)
        }
    }

    private func rollUp(now: Date) async throws {
        for target in StoragePolicy.rollupCutoffs(now: now) {
            try await attempt("Hourly rollup", metadata: ["type": "\(target.type.rawValue)"]) {
                try await entities.rollUpHourly(type: target.type, validRange: target.validRange, olderThan: target.before)
            }
        }
    }

    /// Runs one upkeep piece; a failure is logged and the next piece still runs. A cancellation (a stop, a superseding
    /// run) is no failure: it ends the whole upkeep.
    private func attempt(_ piece: String, metadata: Logger.Metadata = [:], _ work: () async throws -> Void) async throws {
        do {
            try await work()
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            log.error("Database upkeep failed", metadata: metadata.merging(["piece": "\(piece)", "error": "\(error)"]) { current, _ in current })
        }
    }
}

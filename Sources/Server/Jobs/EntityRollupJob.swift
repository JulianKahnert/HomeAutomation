//
//  EntityRollupJob.swift
//  HomeAutomationServer
//

import Foundation
import HAModels
import Logging
import Shared

/// Once an hour: condenses the raw rows of every type whose ``StoragePolicy`` has an hourly rollup
/// (lux, CO₂) once they pass their raw retention, into `entityHourlyAggregates`, and deletes them.
struct EntityRollupJob: Job, Log {
    let entities: any EntityRetentionStore

    func run() async {
        log.info("Starting EntityRollupJob - will run every hour")
        await rollUpOnce()
        for await _ in Timer.publish(every: .hours(1)) {
            await rollUpOnce()
        }
    }

    func rollUpOnce(now: Date = Date()) async {
        for target in StoragePolicy.rollupCutoffs(now: now) {
            do {
                try await entities.rollUpHourly(type: target.type, column: target.column, validRange: target.validRange, olderThan: target.before)
            } catch {
                log.error("Hourly rollup of \(target.type.rawValue) failed: \(error)")
            }
        }
    }
}

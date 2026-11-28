//
//  StoragePolicy.swift
//  HomeAutomationServer
//

import Foundation
import HAModels
import Shared

/// When the daily cleanup and the hourly rollup act on `entityChanges`.
///
/// The rules themselves live in `ValueDescriptor.descriptor(for:).storage`, the only rule table: writing (dead band),
/// the daily cleanup and the hourly rollup all read it. Rules are fixed in code on purpose; there is no config and no
/// DB table.
enum StoragePolicy {
    /// Rows stored per entity in 24 hours above which ``NoisyEntityWarner`` suggests a dead band.
    /// A row of the old wide `entityItems` table cost about 370 B (data plus index); the narrow `entityChanges` row is smaller, so this stays a conservative bound. So 500 rows a day are 500 × 365 × 370 B ≈ 68 MB per entity and year, kept forever.
    static let noisyEntityRowsPerDay = 500

    /// Types whose raw rows the daily cleanup deletes, with the date before which they go.
    /// Types with a rollup are left to the rollup job, which deletes their rows after aggregating them.
    static func cleanupCutoffs(now: Date) -> [(type: CharacteristicsType, before: Date)] {
        CharacteristicsType.allCases.compactMap { type in
            let rule = ValueDescriptor.descriptor(for: type).storage
            guard !rule.hourlyRollup, let days = rule.rawRetentionDays else { return nil }
            return (type, now.addingTimeInterval(-Duration.days(days).timeInterval))
        }
    }

    /// Types the hourly rollup condenses, with the full hour before which raw rows are aggregated and
    /// deleted. Hour-aligned, so an hour is always aggregated from all of its rows at once.
    static func rollupCutoffs(now: Date) -> [(type: CharacteristicsType, validRange: ClosedRange<Double>?, before: Date)] {
        CharacteristicsType.allCases.compactMap { type in
            let rule = ValueDescriptor.descriptor(for: type).storage
            guard rule.hourlyRollup, let days = rule.rawRetentionDays else { return nil }
            let cutoff = now.addingTimeInterval(-Duration.days(days).timeInterval)
            let hour = (cutoff.timeIntervalSince1970 / 3600).rounded(.down) * 3600
            return (type, rule.validRange, Date(timeIntervalSince1970: hour))
        }
    }
}

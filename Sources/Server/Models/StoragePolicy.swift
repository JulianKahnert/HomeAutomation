//
//  StoragePolicy.swift
//  HomeAutomationServer
//

import Foundation
import HAModels
import Shared

/// How one characteristic type is written, kept and condensed in `entityChanges`.
///
/// ``policy(for:)`` is the only rule table: writing (dead band), the daily cleanup and the hourly
/// rollup all read it. Rules are fixed in code on purpose; there is no config and no DB table.
struct StoragePolicy: Sendable, Equatable {
    /// Rules follow the kind of value, not the device.
    enum StorageKind: Sendable, Equatable {
        /// Measured quantities: temperature, humidity, lux, CO₂, battery level, lamp levels.
        case analog
        /// States and events: switch, contact, motion, lock, heating fields and mode.
        case state
        /// Enumerated levels such as HomeKit air quality.
        case enumeration

        init(_ storageClass: ValueDescriptor.StorageRule.Class) {
            switch storageClass {
            case .analog: self = .analog
            case .state: self = .state
            case .enumeration: self = .enumeration
            }
        }
    }

    /// A new value is stored only when it moved far enough from the last stored one, or when the
    /// last stored one is older than `maxInterval`.
    struct DeadBand: Sendable, Equatable {
        enum Threshold: Sendable, Equatable {
            case absolute(Double)
            /// Fraction of the last stored value, e.g. 0.1 for 10 %.
            case relative(Double)
        }

        let threshold: Threshold
        let maxInterval: Duration

        func shouldStore(_ value: Double, at timestamp: Date, lastStored: (value: Double, timestamp: Date)?) -> Bool {
            guard let lastStored else { return true }
            if timestamp.timeIntervalSince(lastStored.timestamp) >= maxInterval.timeInterval {
                return true
            }
            let change = abs(value - lastStored.value)
            switch threshold {
            case .absolute(let limit):
                return change >= limit
            case .relative(let fraction):
                return change >= abs(lastStored.value) * fraction
            }
        }
    }

    enum Rollup: Sendable, Equatable {
        case none
        /// Min, mean, max, last and count per entity and hour in `entityHourlyAggregates`.
        case hourly
    }

    let kind: StorageKind
    let deadBand: DeadBand?
    /// Days a raw row is kept; `nil` keeps it forever.
    let rawRetentionDays: Int?
    let rollup: Rollup
    /// Values outside are sensor errors (CO₂ reports 0 ppm) and are left out of the rollup.
    let validRange: ClosedRange<Double>?

    /// Rows stored per entity in 24 hours above which ``NoisyEntityWarner`` suggests a dead band.
    /// A row of the old wide `entityItems` table cost about 370 B (data plus index); the narrow `entityChanges` row is smaller, so this stays a conservative bound. So 500 rows a day are 500 × 365 × 370 B ≈ 68 MB per entity and year, kept forever.
    static let noisyEntityRowsPerDay = 500

    static func state(_ kind: StorageKind = .state) -> StoragePolicy {
        StoragePolicy(kind: kind, deadBand: nil, rawRetentionDays: nil, rollup: .none, validRange: nil)
    }

    /// A type stored in the database that this server version does not know: kept raw forever.
    static let unknown = state()

    /// The rule comes from the value kind's descriptor; the Server only adds the storage kind.
    static func policy(for type: CharacteristicsType) -> StoragePolicy {
        let rule = ValueDescriptor.descriptor(for: type).storage
        return StoragePolicy(kind: StorageKind(rule.storageClass),
                             deadBand: rule.deadBand.map { DeadBand(threshold: .absolute($0.absoluteChange), maxInterval: $0.maxInterval) },
                             rawRetentionDays: rule.rawRetentionDays,
                             rollup: rule.hourlyRollup ? .hourly : .none,
                             validRange: rule.validRange)
    }

    static func policy(forRawType rawType: String) -> StoragePolicy {
        CharacteristicsType(rawValue: rawType).map(policy(for:)) ?? unknown
    }

    /// Types whose raw rows the daily cleanup deletes, with the date before which they go.
    /// Types with a rollup are left to the rollup job, which deletes their rows after aggregating them.
    static func cleanupCutoffs(now: Date) -> [(type: CharacteristicsType, before: Date)] {
        CharacteristicsType.allCases.compactMap { type in
            let policy = policy(for: type)
            guard policy.rollup == .none, let days = policy.rawRetentionDays else { return nil }
            return (type, now.addingTimeInterval(-Duration.days(days).timeInterval))
        }
    }

    /// Types the hourly rollup condenses, with the full hour before which raw rows are aggregated and
    /// deleted. Hour-aligned, so an hour is always aggregated from all of its rows at once.
    static func rollupCutoffs(now: Date) -> [(type: CharacteristicsType, validRange: ClosedRange<Double>?, before: Date)] {
        CharacteristicsType.allCases.compactMap { type in
            let policy = policy(for: type)
            guard policy.rollup == .hourly, let days = policy.rawRetentionDays else { return nil }
            let cutoff = now.addingTimeInterval(-Duration.days(days).timeInterval)
            let hour = (cutoff.timeIntervalSince1970 / 3600).rounded(.down) * 3600
            return (type, policy.validRange, Date(timeIntervalSince1970: hour))
        }
    }
}

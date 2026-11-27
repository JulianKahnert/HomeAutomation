//
//  StoragePolicy.swift
//  HomeAutomationServer
//

import Foundation
import HAModels
import Shared

/// How one characteristic type is written, kept and condensed in `entityItems`.
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

    /// The `entityItems` column that holds an analog type's value.
    enum ValueColumn: String, Sendable, CaseIterable {
        case illuminanceInLux, carbonDioxideSensorId, temperatureInC, relativeHumidity, pmDensity
        case stateOfCharge, brightness, colorTemperature

        func value(in item: EntityStorageDbItem) -> Double? {
            switch self {
            case .illuminanceInLux: item.illuminanceInLux
            case .carbonDioxideSensorId: item.carbonDioxideSensorId.map(Double.init)
            case .temperatureInC: item.temperatureInC
            case .relativeHumidity: item.relativeHumidity
            case .pmDensity: item.pmDensity
            case .stateOfCharge: item.stateOfCharge.map(Double.init)
            case .brightness: item.brightness.map(Double.init)
            case .colorTemperature: item.colorTemperature.map(Double.init)
            }
        }
    }

    let kind: StorageKind
    let valueColumn: ValueColumn?
    let deadBand: DeadBand?
    /// Days a raw row is kept; `nil` keeps it forever.
    let rawRetentionDays: Int?
    let rollup: Rollup
    /// Values outside are sensor errors (CO₂ reports 0 ppm) and are left out of the rollup.
    let validRange: ClosedRange<Double>?

    /// Rows stored per entity in 24 hours above which ``DatabaseCleanupJob`` suggests a dead band.
    /// An `entityItems` row costs about 370 B (data plus index): 285 B measured in production
    /// (81 MB / 285k rows, Nov 2026) plus about 80 B for `idx_entityItems_type_timestamp` (measured on
    /// mysql:9). So 500 rows a day are 500 × 365 × 370 B ≈ 68 MB per entity and year, kept forever.
    static let noisyEntityRowsPerDay = 500

    static func state(_ kind: StorageKind = .state) -> StoragePolicy {
        StoragePolicy(kind: kind, valueColumn: nil, deadBand: nil, rawRetentionDays: nil, rollup: .none, validRange: nil)
    }

    static func analog(_ column: ValueColumn) -> StoragePolicy {
        StoragePolicy(kind: .analog, valueColumn: column, deadBand: nil, rawRetentionDays: nil, rollup: .none, validRange: nil)
    }

    /// A type stored in the database that this server version does not know: kept raw forever.
    static let unknown = state()

    /// Exhaustive on purpose: a new `CharacteristicsType` does not compile until it gets a value kind here.
    static func policy(for type: CharacteristicsType) -> StoragePolicy {
        switch type {
        case .lightSensor:
            // Lux already jumps in big steps, so a dead band saves little; the rollup after 90 days does.
            StoragePolicy(kind: .analog,
                          valueColumn: .illuminanceInLux,
                          deadBand: nil,
                          rawRetentionDays: 90,
                          rollup: .hourly,
                          validRange: 0...100_000)
        case .carbonDioxideSensorId:
            StoragePolicy(kind: .analog,
                          valueColumn: .carbonDioxideSensorId,
                          deadBand: DeadBand(threshold: .absolute(25), maxInterval: .minutes(15)),
                          rawRetentionDays: 90,
                          rollup: .hourly,
                          validRange: 1...100_000)
        case .temperatureSensor:
            analog(.temperatureInC)
        case .relativeHumiditySensor:
            analog(.relativeHumidity)
        case .pmDensitySensor:
            analog(.pmDensity)
        case .batterySensor:
            analog(.stateOfCharge)
        case .brightness:
            analog(.brightness)
        case .colorTemperature:
            analog(.colorTemperature)
        case .airQualitySensor:
            state(.enumeration)
        case .motionSensor, .contactSensor, .switcher, .color, .valve, .lock, .heating,
             .targetTemperature, .heatingMode, .valvePosition, .temperatureCalibration:
            state()
        }
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
    static func rollupCutoffs(now: Date) -> [(type: CharacteristicsType, column: ValueColumn, validRange: ClosedRange<Double>?, before: Date)] {
        CharacteristicsType.allCases.compactMap { type in
            let policy = policy(for: type)
            guard policy.rollup == .hourly, let days = policy.rawRetentionDays, let column = policy.valueColumn else { return nil }
            let cutoff = now.addingTimeInterval(-Duration.days(days).timeInterval)
            let hour = (cutoff.timeIntervalSince1970 / 3600).rounded(.down) * 3600
            return (type, column, policy.validRange, Date(timeIntervalSince1970: hour))
        }
    }
}

//
//  ValueDescriptor.swift
//  HAModels
//

import Foundation
import Shared

/// What one value kind is: the shape of its value, unit, display and storage rule.
///
/// ``descriptor(for:)`` is the only table and is exhaustive on purpose: a new `CharacteristicsType`
/// does not compile until it has a descriptor.
public struct ValueDescriptor: Sendable, Equatable {
    public enum Shape: Sendable, Equatable {
        case bool, number, text
        /// A text for the case and a number for the end, kept in one row (``Deadline``).
        case textWithNumber
    }

    public enum Display: Sendable, Equatable {
        case boolean(trueLabel: String, falseLabel: String)
        case number(fractionDigits: Int)
        case color
        case enumeration
        case deadline
    }

    /// How a kind is written, kept and condensed (the rules behind `StoragePolicy`).
    public struct StorageRule: Sendable, Equatable {
        /// A new value is stored only when it moved by `absoluteChange` or the last one is older than `maxInterval`.
        public struct DeadBand: Sendable, Equatable {
            public let absoluteChange: Double
            public let maxInterval: Duration

            /// Whether `value` at `timestamp` is worth storing after the last stored one.
            public func shouldStore(_ value: Double, at timestamp: Date, lastStored: (value: Double, timestamp: Date)?) -> Bool {
                guard let lastStored else { return true }
                if timestamp.timeIntervalSince(lastStored.timestamp) >= maxInterval.timeInterval {
                    return true
                }
                return abs(value - lastStored.value) >= absoluteChange
            }
        }

        public let deadBand: DeadBand?
        /// Days a raw row is kept; `nil` keeps it forever.
        public let rawRetentionDays: Int?
        /// Whether the hourly rollup condenses old rows.
        public let hourlyRollup: Bool
        /// Values outside are sensor errors and are left out of the rollup.
        public let validRange: ClosedRange<Double>?

        /// Kept raw forever, no dead band, no rollup.
        static let keepRaw = StorageRule(deadBand: nil, rawRetentionDays: nil, hourlyRollup: false, validRange: nil)
    }

    /// What a value of the right shape must also satisfy to fit the kind.
    public enum Constraint: Sendable, Equatable {
        case none
        /// A number without a fraction.
        case wholeNumber
        /// A number that is the raw value of a ``HeatingMode``.
        case heatingMode
        /// A text of three numbers, "red green blue".
        case colorText
        /// A text ``Deadline`` can parse.
        case deadlineText
    }

    public let shape: Shape
    /// Unit symbol, `nil` for unitless kinds.
    public let unit: String?
    public let display: Display
    public let storage: StorageRule
    public let constraint: Constraint
    /// Whether the app may set a state of this kind through `PUT /entities/state` (the route still accepts only
    /// server-owned entities).
    public let isSettableFromApp: Bool

    /// Whether `value` fits the kind: the right shape and its constraint.
    public func accepts(_ value: Value) -> Bool {
        switch (shape, value) {
        case (.bool, .bool):
            return true
        case (.number, .number(let number)):
            return accepts(number: number)
        case (.text, .text(let text)), (.textWithNumber, .text(let text)):
            return accepts(text: text)
        default:
            return false
        }
    }

    private func accepts(number: Double) -> Bool {
        switch constraint {
        case .wholeNumber:
            return Int(exactly: number) != nil
        case .heatingMode:
            return Int(exactly: number).flatMap(HeatingMode.init(rawValue:)) != nil
        default:
            return true
        }
    }

    private func accepts(text: String) -> Bool {
        switch constraint {
        case .colorText:
            return text.split(separator: " ").compactMap { Float($0) }.count == 3
        case .deadlineText:
            return Deadline(text: text) != nil
        default:
            return true
        }
    }

    private static let lightStorage = StorageRule(
        deadBand: nil,
        rawRetentionDays: 90,
        hourlyRollup: true,
        validRange: 0...100_000
    )

    private static let carbonDioxideStorage = StorageRule(
        deadBand: .init(absoluteChange: 25, maxInterval: .seconds(15 * 60)),
        rawRetentionDays: 90,
        hourlyRollup: true,
        validRange: 1...100_000
    )

    private static func bool(_ type: CharacteristicsType, _ trueLabel: String, _ falseLabel: String, isSettableFromApp: Bool = false) -> ValueDescriptor {
        ValueDescriptor(
            shape: .bool,
            unit: nil,
            display: .boolean(trueLabel: trueLabel, falseLabel: falseLabel),
            storage: .keepRaw,
            constraint: .none,
            isSettableFromApp: isSettableFromApp
        )
    }

    private static func number(
        _ type: CharacteristicsType,
        unit: String?,
        digits: Int = 0,
        storage: StorageRule = .keepRaw,
        constraint: Constraint = .none,
        isSettableFromApp: Bool = false
    ) -> ValueDescriptor {
        ValueDescriptor(
            shape: .number,
            unit: unit,
            display: .number(fractionDigits: digits),
            storage: storage,
            constraint: constraint,
            isSettableFromApp: isSettableFromApp
        )
    }

    private static func structured(_ type: CharacteristicsType, shape: Shape, display: Display, constraint: Constraint) -> ValueDescriptor {
        ValueDescriptor(
            shape: shape,
            unit: nil,
            display: display,
            storage: .keepRaw,
            constraint: constraint,
            isSettableFromApp: false
        )
    }

    public static func descriptor(for type: CharacteristicsType) -> ValueDescriptor {
        switch type {
        case .motionSensor:
            return bool(type, "motion", "no motion")
        case .contactSensor:
            return bool(type, "open", "closed")
        case .switcher:
            return bool(type, "on", "off", isSettableFromApp: true)
        case .valve:
            return bool(type, "open", "closed")
        case .lock:
            return bool(type, "locked", "unlocked")
        case .heating:
            return bool(type, "heating", "idle")
        case .lightSensor:
            return number(type, unit: "lx", storage: lightStorage)
        case .carbonDioxideSensorId:
            return number(type, unit: "ppm", storage: carbonDioxideStorage, constraint: .wholeNumber)
        case .temperatureSensor:
            return number(type, unit: "°C", digits: 1)
        case .relativeHumiditySensor:
            return number(type, unit: "%")
        case .pmDensitySensor:
            return number(type, unit: "µg/m³")
        case .batterySensor:
            return number(type, unit: "%", constraint: .wholeNumber)
        case .brightness:
            return number(type, unit: "%", constraint: .wholeNumber)
        case .colorTemperature:
            return number(type, unit: nil, digits: 2)
        case .airQualitySensor:
            return number(type, unit: nil, storage: StorageRule.keepRaw, constraint: .wholeNumber)
        case .targetTemperature:
            return number(type, unit: "°C", digits: 1, storage: .keepRaw, isSettableFromApp: true)
        case .heatingMode:
            return number(type, unit: nil, storage: .keepRaw, constraint: .heatingMode, isSettableFromApp: true)
        case .valvePosition:
            return number(type, unit: "%", storage: .keepRaw, constraint: .wholeNumber)
        case .temperatureCalibration:
            return number(type, unit: "°C", digits: 1, storage: .keepRaw)
        case .energyPrice:
            return number(type, unit: "€/kWh", digits: 3)
        case .deadline:
            return structured(type, shape: .textWithNumber, display: .deadline, constraint: .deadlineText)
        case .color:
            return structured(type, shape: .text, display: .color, constraint: .colorText)
        }
    }
}

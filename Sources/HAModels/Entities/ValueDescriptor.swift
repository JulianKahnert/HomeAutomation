//
//  ValueDescriptor.swift
//  HAModels
//

import Foundation

/// What one value kind is: the shape of its value, unit, display and storage rule.
///
/// ``descriptor(for:)`` is the only table and is exhaustive on purpose: a new `CharacteristicsType`
/// does not compile until it has a descriptor.
public struct ValueDescriptor: Sendable, Equatable {
    public enum Shape: Sendable, Equatable {
        case bool, number, text
    }

    public enum Display: Sendable, Equatable {
        case boolean(trueLabel: String, falseLabel: String)
        case number(fractionDigits: Int)
        case color
        case enumeration
    }

    /// How a kind is written, kept and condensed (the rules behind `StoragePolicy`).
    public struct StorageRule: Sendable, Equatable {
        /// Rules follow the kind of value, not the device.
        public enum Class: Sendable, Equatable {
            /// Measured quantities: temperature, humidity, lux, CO₂, battery level, lamp levels.
            case analog
            /// States and events: switch, contact, motion, lock, heating fields and mode.
            case state
            /// Enumerated levels such as HomeKit air quality.
            case enumeration
        }

        /// A new value is stored only when it moved by `absoluteChange` or the last one is older than `maxInterval`.
        public struct DeadBand: Sendable, Equatable {
            public let absoluteChange: Double
            public let maxInterval: Duration
        }

        public let storageClass: Class
        public let deadBand: DeadBand?
        /// Days a raw row is kept; `nil` keeps it forever.
        public let rawRetentionDays: Int?
        /// Whether the hourly rollup condenses old rows.
        public let hourlyRollup: Bool
        /// Values outside are sensor errors and are left out of the rollup.
        public let validRange: ClosedRange<Double>?

        static let state = StorageRule(storageClass: .state, deadBand: nil, rawRetentionDays: nil, hourlyRollup: false, validRange: nil)
        static let analog = StorageRule(storageClass: .analog, deadBand: nil, rawRetentionDays: nil, hourlyRollup: false, validRange: nil)
    }

    public let kind: ValueKind
    public let shape: Shape
    /// Unit symbol, `nil` for unitless kinds.
    public let unit: String?
    public let display: Display
    public let storage: StorageRule
    /// Whether the app may set a server-owned entity of this kind through the general route.
    public private(set) var appSettable = false

    private static func bool(_ type: CharacteristicsType, _ yes: String, _ no: String) -> ValueDescriptor {
        ValueDescriptor(kind: type.valueKind, shape: .bool, unit: nil, display: .boolean(trueLabel: yes, falseLabel: no), storage: .state)
    }

    private static func number(_ type: CharacteristicsType, unit: String?, digits: Int = 0,
                               storage: StorageRule = .analog) -> ValueDescriptor {
        ValueDescriptor(kind: type.valueKind, shape: .number, unit: unit, display: .number(fractionDigits: digits), storage: storage)
    }

    /// Kinds a server-owned entity can hold that the user sets in the app: a switch (fireplace), a mode, a target.
    private static let appSettableTypes: [CharacteristicsType] = [.switcher, .heatingMode, .targetTemperature]

    public static func descriptor(for type: CharacteristicsType) -> ValueDescriptor {
        var descriptor = table(for: type)
        descriptor.appSettable = appSettableTypes.contains(type)
        return descriptor
    }

    private static func table(for type: CharacteristicsType) -> ValueDescriptor {
        switch type {
        case .motionSensor: bool(type, "motion", "no motion")
        case .contactSensor: bool(type, "open", "closed")
        case .switcher: bool(type, "on", "off")
        case .valve: bool(type, "open", "closed")
        case .lock: bool(type, "locked", "unlocked")
        case .heating: bool(type, "heating", "idle")
        case .lightSensor:
            number(type, unit: "lx", storage: StorageRule(storageClass: .analog, deadBand: nil, rawRetentionDays: 90,
                                                           hourlyRollup: true, validRange: 0...100_000))
        case .carbonDioxideSensorId:
            number(type, unit: "ppm", storage: StorageRule(storageClass: .analog,
                                                            deadBand: .init(absoluteChange: 25, maxInterval: .seconds(15 * 60)),
                                                            rawRetentionDays: 90, hourlyRollup: true, validRange: 1...100_000))
        case .temperatureSensor: number(type, unit: "°C", digits: 1)
        case .relativeHumiditySensor: number(type, unit: "%")
        case .pmDensitySensor: number(type, unit: "µg/m³")
        case .batterySensor: number(type, unit: "%")
        case .brightness: number(type, unit: "%")
        case .colorTemperature: number(type, unit: nil, digits: 2)
        case .airQualitySensor: number(type, unit: nil, storage: StorageRule(storageClass: .enumeration, deadBand: nil,
                                                                              rawRetentionDays: nil, hourlyRollup: false, validRange: nil))
        case .targetTemperature: number(type, unit: "°C", digits: 1, storage: .state)
        case .heatingMode: number(type, unit: nil, storage: .state)
        case .valvePosition: number(type, unit: "%", storage: .state)
        case .temperatureCalibration: number(type, unit: "°C", digits: 1, storage: .state)
        case .color:
            ValueDescriptor(kind: type.valueKind, shape: .text, unit: nil, display: .color, storage: .state)
        }
    }
}

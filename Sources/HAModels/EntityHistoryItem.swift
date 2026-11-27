//
//  EntityHistoryItem.swift
//  HAModels
//
//  Created for entity history visualization feature
//

import Foundation

/// Represents a single historical data point for an entity
public struct EntityHistoryItem: Identifiable, Sendable, Codable, Equatable, Hashable {
    public let id: UUID
    public let timestamp: Date
    /// Where the change came from; `nil` for an item that is no single change, such as an hourly aggregate.
    public let origin: String?
    /// When the entity last reported, a replay included. Only set on the newest item of a history, and only while the
    /// server holds it in memory; `nil` after a restart until the first report.
    public let lastReport: Date?
    /// The value kind (`ValueKind.rawValue`) and the value. A kind this build does not know still arrives here, with
    /// its raw value. The typed accessors below derive from the pair.
    public let valueKind: String?
    public let value: Value?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        origin: String? = nil,
        lastReport: Date? = nil,
        valueKind: String? = nil,
        value: Value? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.origin = origin
        self.lastReport = lastReport
        self.valueKind = valueKind
        self.value = value
    }
}

extension EntityHistoryItem {
    public init(_ item: EntityStorageItem) {
        self.init(timestamp: item.timestamp,
                  origin: item.origin.rawValue,
                  lastReport: item.lastReport,
                  valueKind: item.kind?.rawValue,
                  value: item.value)
    }

    private func bool(_ type: CharacteristicsType) -> Bool? {
        if valueKind == type.rawValue, case .bool(let bool)? = value { bool } else { nil }
    }

    private func number(_ type: CharacteristicsType) -> Double? {
        if valueKind == type.rawValue, case .number(let number)? = value { number } else { nil }
    }

    private func int(_ type: CharacteristicsType) -> Int? {
        number(type).flatMap { Int(exactly: $0) }
    }

    private var colorComponents: [Float]? {
        guard valueKind == CharacteristicsType.color.rawValue, case .text(let text)? = value else { return nil }
        let parts = text.split(separator: " ").compactMap { Float($0) }
        return parts.count == 3 ? parts : nil
    }

    public var motionDetected: Bool? { bool(.motionSensor) }
    public var illuminanceInLux: Double? { number(.lightSensor) }
    public var isDeviceOn: Bool? { bool(.switcher) }
    public var brightness: Int? { int(.brightness) }
    public var colorTemperature: Float? { number(.colorTemperature).map(Float.init) }
    public var colorRed: Float? { colorComponents?[0] }
    public var colorGreen: Float? { colorComponents?[1] }
    public var colorBlue: Float? { colorComponents?[2] }
    public var isContactOpen: Bool? { bool(.contactSensor) }
    public var isDoorLocked: Bool? { bool(.lock) }
    public var stateOfCharge: Int? { int(.batterySensor) }
    public var isHeaterActive: Bool? { bool(.heating) }
    public var temperatureInC: Double? { number(.temperatureSensor) }
    public var relativeHumidity: Double? { number(.relativeHumiditySensor) }
    public var carbonDioxideSensorId: Int? { int(.carbonDioxideSensorId) }
    public var pmDensity: Double? { number(.pmDensitySensor) }
    public var airQuality: Int? { int(.airQualitySensor) }
    public var valveOpen: Bool? { bool(.valve) }
    public var targetTemperatureInC: Double? { number(.targetTemperature) }
    public var heatingMode: HeatingMode? { int(.heatingMode).flatMap(HeatingMode.init(rawValue:)) }
    public var valvePositionPercent: Int? { int(.valvePosition) }
    public var temperatureCalibrationInC: Double? { number(.temperatureCalibration) }

    /// The descriptor of the value kind; `nil` for a kind this build does not know.
    public var descriptor: ValueDescriptor? {
        valueKind.flatMap { ValueKind(rawValue: $0).descriptor }
    }

    /// The raw value as text, for a kind without a descriptor.
    public var rawValueDescription: String? {
        switch value {
        case .bool(let bool): String(bool)
        case .number(let number): abs(number) < 1e15 && number.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(number)) : String(number)
        case .text(let text): text
        case nil: nil
        }
    }

    /// Human-readable description of the primary value
    public var valueDescription: String {
        if let valueKind, ValueKind(rawValue: valueKind).descriptor == nil, let rawValueDescription {
            return "\(valueKind): \(rawValueDescription)"
        }
        if let temperatureInC {
            return "\(String(format: "%.1f", temperatureInC))°C"
        }
        if let relativeHumidity {
            return "\(String(format: "%.1f", relativeHumidity))%"
        }
        if let carbonDioxideSensorId {
            return "\(carbonDioxideSensorId) ppm"
        }
        if let airQuality {
            return "AQI: \(airQuality)"
        }
        if let pmDensity {
            return "\(String(format: "%.1f", pmDensity)) µg/m³"
        }
        if let illuminanceInLux {
            return "\(String(format: "%.1f", illuminanceInLux)) lux"
        }
        if let brightness {
            return "\(brightness)%"
        }
        if let stateOfCharge {
            return "\(stateOfCharge)%"
        }
        if let colorTemperature {
            return "CT: \(String(format: "%.2f", colorTemperature))"
        }
        if let isDeviceOn {
            return isDeviceOn ? "On" : "Off"
        }
        if let motionDetected {
            return motionDetected ? "Motion" : "No Motion"
        }
        if let isContactOpen {
            return isContactOpen ? "Open" : "Closed"
        }
        if let isDoorLocked {
            return isDoorLocked ? "Locked" : "Unlocked"
        }
        if let isHeaterActive {
            return isHeaterActive ? "Active" : "Inactive"
        }
        if let valveOpen {
            return valveOpen ? "Open" : "Closed"
        }
        if let valvePositionPercent {
            return "Valve \(valvePositionPercent)%"
        }
        if let temperatureCalibrationInC {
            return "Offset \(String(format: "%+.1f", temperatureCalibrationInC))°C"
        }
        if let targetTemperatureInC {
            return "Target \(String(format: "%.1f", targetTemperatureInC))°C"
        }
        if let heatingMode {
            return "Mode \(heatingMode.name)"
        }
        // Color as hue
        if let colorRed, let colorGreen, let colorBlue {
            let hue = Double(RGB(red: colorRed, green: colorGreen, blue: colorBlue).hue)
            return "\(String(format: "%.0f", hue))° hue"
        }
        return "No data"
    }
}

/// The history of one entity, as returned per entity of a room.
public struct EntityHistory: Sendable, Equatable {
    public let entityId: EntityId
    /// Newest first.
    public let items: [EntityHistoryItem]

    public init(entityId: EntityId, items: [EntityHistoryItem]) {
        self.entityId = entityId
        self.items = items
    }
}

/// Response wrapper for paginated entity history
public struct EntityHistoryResponse: Sendable, Codable, Equatable {
    public let items: [EntityHistoryItem]
    public let nextCursor: Date?

    public init(items: [EntityHistoryItem], nextCursor: Date?) {
        self.items = items
        self.nextCursor = nextCursor
    }

    public var hasMore: Bool {
        nextCursor != nil
    }
}

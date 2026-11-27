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
    public let motionDetected: Bool?
    public let illuminanceInLux: Double?
    public let isDeviceOn: Bool?
    public let brightness: Int?
    public let colorTemperature: Float?
    public let colorRed: Float?
    public let colorGreen: Float?
    public let colorBlue: Float?
    public let isContactOpen: Bool?
    public let isDoorLocked: Bool?
    public let stateOfCharge: Int?
    public let isHeaterActive: Bool?
    public let temperatureInC: Double?
    public let relativeHumidity: Double?
    public let carbonDioxideSensorId: Int?
    public let pmDensity: Double?
    public let airQuality: Int?
    public let valveOpen: Bool?
    public let targetTemperatureInC: Double?
    public let heatingMode: HeatingMode?
    public let valvePositionPercent: Int?
    public let temperatureCalibrationInC: Double?
    /// Where the change came from; `nil` for an item that is no single change, such as an hourly aggregate.
    public let origin: String?
    /// When the entity last reported, a replay included. Only set on the newest item of a history, and only while the
    /// server holds it in memory; `nil` after a restart until the first report.
    public let lastReport: Date?
    /// The generic form of the value: its value kind (`ValueKind.rawValue`) and the value. A kind this build does
    /// not know still arrives here, with its raw value.
    public let valueKind: String?
    public let value: Value?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        motionDetected: Bool? = nil,
        illuminanceInLux: Double? = nil,
        isDeviceOn: Bool? = nil,
        brightness: Int? = nil,
        colorTemperature: Float? = nil,
        colorRed: Float? = nil,
        colorGreen: Float? = nil,
        colorBlue: Float? = nil,
        isContactOpen: Bool? = nil,
        isDoorLocked: Bool? = nil,
        stateOfCharge: Int? = nil,
        isHeaterActive: Bool? = nil,
        temperatureInC: Double? = nil,
        relativeHumidity: Double? = nil,
        carbonDioxideSensorId: Int? = nil,
        pmDensity: Double? = nil,
        airQuality: Int? = nil,
        valveOpen: Bool? = nil,
        targetTemperatureInC: Double? = nil,
        heatingMode: HeatingMode? = nil,
        valvePositionPercent: Int? = nil,
        temperatureCalibrationInC: Double? = nil,
        origin: String? = nil,
        lastReport: Date? = nil,
        valueKind: String? = nil,
        value: Value? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.motionDetected = motionDetected
        self.illuminanceInLux = illuminanceInLux
        self.isDeviceOn = isDeviceOn
        self.brightness = brightness
        self.colorTemperature = colorTemperature
        self.colorRed = colorRed
        self.colorGreen = colorGreen
        self.colorBlue = colorBlue
        self.isContactOpen = isContactOpen
        self.isDoorLocked = isDoorLocked
        self.stateOfCharge = stateOfCharge
        self.isHeaterActive = isHeaterActive
        self.temperatureInC = temperatureInC
        self.relativeHumidity = relativeHumidity
        self.carbonDioxideSensorId = carbonDioxideSensorId
        self.pmDensity = pmDensity
        self.airQuality = airQuality
        self.valveOpen = valveOpen
        self.targetTemperatureInC = targetTemperatureInC
        self.heatingMode = heatingMode
        self.valvePositionPercent = valvePositionPercent
        self.temperatureCalibrationInC = temperatureCalibrationInC
        self.origin = origin
        self.lastReport = lastReport
        if let valueKind, let value {
            self.valueKind = valueKind
            self.value = value
        } else if let derived = Self.genericValue(motionDetected: motionDetected, illuminanceInLux: illuminanceInLux,
                                                  isDeviceOn: isDeviceOn, brightness: brightness,
                                                  colorTemperature: colorTemperature,
                                                  color: [colorRed, colorGreen, colorBlue], isContactOpen: isContactOpen,
                                                  isDoorLocked: isDoorLocked, stateOfCharge: stateOfCharge,
                                                  isHeaterActive: isHeaterActive, temperatureInC: temperatureInC,
                                                  relativeHumidity: relativeHumidity,
                                                  carbonDioxideSensorId: carbonDioxideSensorId, pmDensity: pmDensity,
                                                  airQuality: airQuality, valveOpen: valveOpen,
                                                  targetTemperatureInC: targetTemperatureInC, heatingMode: heatingMode,
                                                  valvePositionPercent: valvePositionPercent,
                                                  temperatureCalibrationInC: temperatureCalibrationInC) {
            self.valueKind = derived.kind.rawValue
            self.value = derived.value
        } else {
            self.valueKind = nil
            self.value = nil
        }
    }

    /// Kind and value of the first typed field that is set; the same order as `EntityStorageItem.genericValue`.
    private static func genericValue(
        motionDetected: Bool?, illuminanceInLux: Double?, isDeviceOn: Bool?, brightness: Int?, colorTemperature: Float?,
        color: [Float?], isContactOpen: Bool?, isDoorLocked: Bool?, stateOfCharge: Int?, isHeaterActive: Bool?,
        temperatureInC: Double?, relativeHumidity: Double?, carbonDioxideSensorId: Int?, pmDensity: Double?,
        airQuality: Int?, valveOpen: Bool?, targetTemperatureInC: Double?, heatingMode: HeatingMode?,
        valvePositionPercent: Int?, temperatureCalibrationInC: Double?
    ) -> (kind: ValueKind, value: Value)? {
        func make(_ type: CharacteristicsType, _ value: Value) -> (kind: ValueKind, value: Value) { (type.valueKind, value) }
        if let motionDetected { return make(.motionSensor, .bool(motionDetected)) }
        if let illuminanceInLux { return make(.lightSensor, .number(illuminanceInLux)) }
        if let isDeviceOn { return make(.switcher, .bool(isDeviceOn)) }
        if let brightness { return make(.brightness, .number(Double(brightness))) }
        if let colorTemperature { return make(.colorTemperature, .number(Double(colorTemperature))) }
        if let red = color[0], let green = color[1], let blue = color[2] { return make(.color, .text("\(red) \(green) \(blue)")) }
        if let isContactOpen { return make(.contactSensor, .bool(isContactOpen)) }
        if let isDoorLocked { return make(.lock, .bool(isDoorLocked)) }
        if let stateOfCharge { return make(.batterySensor, .number(Double(stateOfCharge))) }
        if let isHeaterActive { return make(.heating, .bool(isHeaterActive)) }
        if let temperatureInC { return make(.temperatureSensor, .number(temperatureInC)) }
        if let relativeHumidity { return make(.relativeHumiditySensor, .number(relativeHumidity)) }
        if let carbonDioxideSensorId { return make(.carbonDioxideSensorId, .number(Double(carbonDioxideSensorId))) }
        if let pmDensity { return make(.pmDensitySensor, .number(pmDensity)) }
        if let airQuality { return make(.airQualitySensor, .number(Double(airQuality))) }
        if let valveOpen { return make(.valve, .bool(valveOpen)) }
        if let targetTemperatureInC { return make(.targetTemperature, .number(targetTemperatureInC)) }
        if let heatingMode { return make(.heatingMode, .number(Double(heatingMode.rawValue))) }
        if let valvePositionPercent { return make(.valvePosition, .number(Double(valvePositionPercent))) }
        if let temperatureCalibrationInC { return make(.temperatureCalibration, .number(temperatureCalibrationInC)) }
        return nil
    }
}

extension EntityHistoryItem {
    public init(_ item: EntityStorageItem) {
        self.init(timestamp: item.timestamp,
                  motionDetected: item.motionDetected,
                  illuminanceInLux: item.illuminance?.value,
                  isDeviceOn: item.isDeviceOn,
                  brightness: item.brightness,
                  colorTemperature: item.colorTemperature,
                  colorRed: item.color?.red,
                  colorGreen: item.color?.green,
                  colorBlue: item.color?.blue,
                  isContactOpen: item.isContactOpen,
                  isDoorLocked: item.isDoorLocked,
                  stateOfCharge: item.stateOfCharge,
                  isHeaterActive: item.isHeaterActive,
                  temperatureInC: item.temperatureInC?.value,
                  relativeHumidity: item.relativeHumidity,
                  carbonDioxideSensorId: item.carbonDioxideSensorId,
                  pmDensity: item.pmDensity,
                  airQuality: item.airQuality,
                  valveOpen: item.valveOpen,
                  targetTemperatureInC: item.targetTemperatureInC,
                  heatingMode: item.heatingMode,
                  valvePositionPercent: item.valvePositionPercent,
                  temperatureCalibrationInC: item.temperatureCalibrationInC,
                  origin: item.origin.rawValue,
                  lastReport: item.lastReport,
                  valueKind: item.genericValue?.kind.rawValue,
                  value: item.genericValue?.value)
    }

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

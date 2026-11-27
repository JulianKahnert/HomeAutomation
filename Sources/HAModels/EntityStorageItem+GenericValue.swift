//
//  EntityStorageItem+GenericValue.swift
//  HAModels
//

import Foundation

/// The generic form of a state: its value kind and one value. It lives next to the typed fields;
/// nothing reads it yet (T13 to T16 move the readers over).
public extension EntityStorageItem {
    /// Kind and value of the first typed field that is set, `nil` for an item without a value.
    var genericValue: (kind: ValueKind, value: Value)? {
        func make(_ type: CharacteristicsType, _ value: Value) -> (kind: ValueKind, value: Value) { (type.valueKind, value) }
        if let motionDetected { return make(.motionSensor, .bool(motionDetected)) }
        if let _illuminanceInLux { return make(.lightSensor, .number(_illuminanceInLux)) }
        if let isDeviceOn { return make(.switcher, .bool(isDeviceOn)) }
        if let brightness { return make(.brightness, .number(Double(brightness))) }
        if let colorTemperature { return make(.colorTemperature, .number(Double(colorTemperature))) }
        if let color { return make(.color, .text("\(color.red) \(color.green) \(color.blue)")) }
        if let isContactOpen { return make(.contactSensor, .bool(isContactOpen)) }
        if let isDoorLocked { return make(.lock, .bool(isDoorLocked)) }
        if let stateOfCharge { return make(.batterySensor, .number(Double(stateOfCharge))) }
        if let isHeaterActive { return make(.heating, .bool(isHeaterActive)) }
        if let _temperatureInC { return make(.temperatureSensor, .number(_temperatureInC)) }
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

    /// Builds the typed form from kind and value; `nil` when the kind is unknown or the value does not fit it.
    init?(entityId: EntityId, timestamp: Date = Date(), kind: ValueKind, value: Value, origin: Origin = .homekit) {
        guard let type = kind.characteristicsType else { return nil }
        func bool() -> Bool? { if case .bool(let value) = value { value } else { nil } }
        func number() -> Double? { if case .number(let value) = value { value } else { nil } }
        func int() -> Int? { number().flatMap { Int(exactly: $0) } }

        let created: EntityStorageItem?
        switch type {
        case .motionSensor: created = bool().map { .init(entityId: entityId, timestamp: timestamp, motionDetected: $0, origin: origin) }
        case .lightSensor: created = number().map { .init(entityId: entityId, timestamp: timestamp, illuminance: .init(value: $0, unit: .lux), origin: origin) }
        case .switcher: created = bool().map { .init(entityId: entityId, timestamp: timestamp, isDeviceOn: $0, origin: origin) }
        case .brightness: created = int().map { .init(entityId: entityId, timestamp: timestamp, brightness: $0, origin: origin) }
        case .colorTemperature: created = number().map { .init(entityId: entityId, timestamp: timestamp, colorTemperature: Float($0), origin: origin) }
        case .color:
            if case .text(let text) = value {
                let parts = text.split(separator: " ").compactMap { Float($0) }
                created = parts.count == 3
                    ? .init(entityId: entityId, timestamp: timestamp, color: RGB(red: parts[0], green: parts[1], blue: parts[2]), origin: origin)
                    : nil
            } else {
                created = nil
            }
        case .contactSensor: created = bool().map { .init(entityId: entityId, timestamp: timestamp, isContactOpen: $0, origin: origin) }
        case .lock: created = bool().map { .init(entityId: entityId, timestamp: timestamp, isDoorLocked: $0, origin: origin) }
        case .batterySensor: created = int().map { .init(entityId: entityId, timestamp: timestamp, stateOfCharge: $0, origin: origin) }
        case .heating: created = bool().map { .init(entityId: entityId, timestamp: timestamp, isHeaterActive: $0, origin: origin) }
        case .temperatureSensor: created = number().map { .init(entityId: entityId, timestamp: timestamp, temperatureInC: .init(value: $0, unit: .celsius), origin: origin) }
        case .relativeHumiditySensor: created = number().map { .init(entityId: entityId, timestamp: timestamp, relativeHumidity: $0, origin: origin) }
        case .carbonDioxideSensorId: created = int().map { .init(entityId: entityId, timestamp: timestamp, carbonDioxideSensorId: $0, origin: origin) }
        case .pmDensitySensor: created = number().map { .init(entityId: entityId, timestamp: timestamp, pmDensity: $0, origin: origin) }
        case .airQualitySensor: created = int().map { .init(entityId: entityId, timestamp: timestamp, airQuality: $0, origin: origin) }
        case .valve: created = bool().map { .init(entityId: entityId, timestamp: timestamp, valveOpen: $0, origin: origin) }
        case .targetTemperature: created = number().map { .init(entityId: entityId, timestamp: timestamp, targetTemperatureInC: $0, origin: origin) }
        case .heatingMode:
            created = int().flatMap(HeatingMode.init(rawValue:)).map { .init(entityId: entityId, timestamp: timestamp, heatingMode: $0, origin: origin) }
        case .valvePosition: created = int().map { .init(entityId: entityId, timestamp: timestamp, valvePositionPercent: $0, origin: origin) }
        case .temperatureCalibration: created = number().map { .init(entityId: entityId, timestamp: timestamp, temperatureCalibrationInC: $0, origin: origin) }
        }
        guard let created else { return nil }
        self = created
    }
}

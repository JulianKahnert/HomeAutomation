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
        if let deadline { return make(.deadline, .text(deadline.text)) }
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
        case .deadline:
            if case .text(let text) = value {
                created = Deadline(text: text).map { .init(entityId: entityId, timestamp: timestamp, deadline: $0, origin: origin) }
            } else {
                created = nil
            }
        }
        guard let created else { return nil }
        self = created
    }
}

public extension EntityStorageItem {
    /// The value of the field that belongs to `type`, `nil` when it is not set. Unlike ``genericValue`` it never
    /// picks another field of the item.
    func value(of type: CharacteristicsType) -> Value? {
        switch type {
        case .motionSensor: motionDetected.map { .bool($0) }
        case .lightSensor: _illuminanceInLux.map { .number($0) }
        case .switcher: isDeviceOn.map { .bool($0) }
        case .brightness: brightness.map { .number(Double($0)) }
        case .colorTemperature: colorTemperature.map { .number(Double($0)) }
        case .color: color.map { .text("\($0.red) \($0.green) \($0.blue)") }
        case .contactSensor: isContactOpen.map { .bool($0) }
        case .lock: isDoorLocked.map { .bool($0) }
        case .batterySensor: stateOfCharge.map { .number(Double($0)) }
        case .heating: isHeaterActive.map { .bool($0) }
        case .temperatureSensor: _temperatureInC.map { .number($0) }
        case .relativeHumiditySensor: relativeHumidity.map { .number($0) }
        case .carbonDioxideSensorId: carbonDioxideSensorId.map { .number(Double($0)) }
        case .pmDensitySensor: pmDensity.map { .number($0) }
        case .airQualitySensor: airQuality.map { .number(Double($0)) }
        case .valve: valveOpen.map { .bool($0) }
        case .targetTemperature: targetTemperatureInC.map { .number($0) }
        case .heatingMode: heatingMode.map { .number(Double($0.rawValue)) }
        case .valvePosition: valvePositionPercent.map { .number(Double($0)) }
        case .temperatureCalibration: temperatureCalibrationInC.map { .number($0) }
        case .deadline: deadline.map { .text($0.text) }
        }
    }
}

/// The wire form (protocol version 3): entity, timestamp, value kind, one value and origin. The typed fields
/// do not cross the wire; `lastReport` is memory only and stays off it.
extension EntityStorageItem {
    private enum WireKeys: String, CodingKey {
        case entityId, timestamp, kind, value, origin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: WireKeys.self)
        let entityId = try container.decode(EntityId.self, forKey: .entityId)
        let timestamp = try container.decode(Date.self, forKey: .timestamp)
        let origin = try container.decodeIfPresent(Origin.self, forKey: .origin) ?? .homekit
        guard let kind = try container.decodeIfPresent(ValueKind.self, forKey: .kind) else {
            self.init(entityId: entityId, timestamp: timestamp, origin: origin)
            return
        }
        let value = try container.decode(Value.self, forKey: .value)
        guard let item = EntityStorageItem(entityId: entityId, timestamp: timestamp, kind: kind, value: value, origin: origin) else {
            throw DecodingError.dataCorruptedError(forKey: .value, in: container, debugDescription: "Value does not fit the value kind \(kind.rawValue)")
        }
        self = item
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: WireKeys.self)
        try container.encode(entityId, forKey: .entityId)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(origin, forKey: .origin)
        if let generic = genericValue {
            try container.encode(generic.kind, forKey: .kind)
            try container.encode(generic.value, forKey: .value)
        }
    }
}

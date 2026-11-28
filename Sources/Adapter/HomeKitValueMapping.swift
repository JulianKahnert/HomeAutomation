//
//  HomeKitValueMapping.swift
//  Adapter
//

import Foundation
import HAModels

/// Turns the raw value HomeKit reports for a characteristic into the ``Value`` of its entity.
///
/// A pure function of the characteristic type of the entity and what HomeKit said, so every type is tested
/// without HomeKit. The HomeKit constant it compares with is written out as its HAP UUID and checked
/// against the HomeKit symbol in `HomeKitValueMappingTests`.
enum HomeKitValueMapping {
    // Characteristics
    static let occupancyDetectedCharacteristic = "00000071-0000-1000-8000-0026BB765291"

    /// What the mapping needs to know about the characteristic besides the value.
    struct Context {
        var characteristicType: String
        var minimumValue: Double?
        var maximumValue: Double?
        /// The values of the `Saturation` and `Brightness` characteristics of the same service, read for a colour.
        var saturation: Any?
        var brightness: Any?
    }

    /// The value for `raw`, as HomeKit reported it; `nil` when it is not what the characteristic promises.
    static func value(_ type: CharacteristicsType, raw: Any?, context: Context) -> Value? {
        switch type {
        case .motionSensor:
            if context.characteristicType == occupancyDetectedCharacteristic {
                return .bool((raw as? Int64) == 1)
            }
            return (raw as? Bool).map { .bool($0) }
        case .lightSensor, .temperatureSensor, .relativeHumiditySensor:
            return (raw as? Double).map { .number($0) }
        case .switcher:
            return (raw as? Bool).map { .bool($0) }
        case .contactSensor:
            // HMCharacteristicValueContactState: 0 detected (closed), 1 not detected (open)
            guard let state = raw as? Int, (0...1).contains(state) else { return nil }
            return .bool(state != 0)
        case .lock:
            // HMCharacteristicValueLockMechanismState: 0 unsecured, 1 secured, 2 jammed, 3 unknown
            guard let state = raw as? Int, (0...3).contains(state) else { return nil }
            return .bool(state == 1)
        case .batterySensor:
            return (raw as? Int64).map { .number(Double(Int($0))) }
        case .heating:
            // HMCharacteristicValueActivationState: 0 inactive, 1 active
            guard let state = raw as? Int, (0...1).contains(state) else { return nil }
            return .bool(state == 1)
        case .brightness, .airQualitySensor:
            return (raw as? Int).map { .number(Double($0)) }
        case .colorTemperature:
            return colorTemperature(mired: raw as? Int, context: context)
        case .color:
            return color(hue: raw as? Float, context: context)
        case .carbonDioxideSensorId:
            return (raw as? Float).map { .number(Double(Int($0))) }
        case .pmDensitySensor:
            return (raw as? Float).map { .number(Double($0)) }
        case .targetTemperature:
            return (raw as? NSNumber).map { .number($0.doubleValue) }
        case .heatingMode:
            guard let rawMode = (raw as? NSNumber)?.intValue,
                  let mode = HeatingControlCharacteristic.heatingMode(rawValue: rawMode, characteristicType: context.characteristicType) else { return nil }
            return .number(Double(mode.rawValue))
        case .valvePosition:
            return (raw as? NSNumber).map { .number(Double($0.intValue)) }
        case .valve:
            // HMCharacteristicValueInUseState of the `In Use` characteristic: 0 not in use, 1 in use (the valve is open)
            guard let state = raw as? Int, (0...1).contains(state) else { return nil }
            return .bool(state == 1)
        case .temperatureCalibration, .energyPrice, .deadline:
            return nil
        }
    }

    /// HomeKit reports the colour temperature in mired; 0 is warm and 1 cold, the same scale `setColorTemperature` uses.
    private static func colorTemperature(mired: Int?, context: Context) -> Value? {
        guard let mired, let minimumValue = context.minimumValue, let maximumValue = context.maximumValue else { return nil }
        let minimum = Float(minimumValue)
        let range = Float(maximumValue) - minimum
        guard range > 0 else { return nil }
        // Invert: a lower mired is colder light.
        return .number(Double(1 - (Float(mired) - minimum) / range))
    }

    /// Hue in degrees, with the saturation and brightness (percent) of the same service, as the "r g b" text of the value.
    private static func color(hue: Float?, context: Context) -> Value? {
        guard let hue else { return nil }
        let saturation = (context.saturation as? Float ?? 100.0) / 100.0
        let brightness = (context.brightness as? Float ?? 100.0) / 100.0
        let color = rgb(h: hue / 360.0, s: saturation, v: brightness)
        return .text("\(color.red) \(color.green) \(color.blue)")
    }
}

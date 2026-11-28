//
//  HomeKitValueMapping.swift
//  Adapter
//

import Foundation
import HAModels

/// Turns the raw value HomeKit reports for a characteristic into the ``Value`` of its entity.
///
/// A pure function of the characteristic type of the entity and what HomeKit said, so every type is tested
/// without HomeKit. The HomeKit constants it compares with are written out as their HAP UUIDs and checked
/// against the HomeKit symbols in `HomeKitValueMappingTests`.
enum HomeKitValueMapping {
    // Services
    static let occupancySensorService = "00000086-0000-1000-8000-0026BB765291"
    static let motionSensorService = "00000085-0000-1000-8000-0026BB765291"
    static let lightSensorService = "00000084-0000-1000-8000-0026BB765291"
    static let contactSensorService = "00000080-0000-1000-8000-0026BB765291"
    static let lockMechanismService = "00000045-0000-1000-8000-0026BB765291"
    static let batteryService = "00000096-0000-1000-8000-0026BB765291"
    // Characteristics
    static let occupancyDetectedCharacteristic = "00000071-0000-1000-8000-0026BB765291"
    static let motionDetectedCharacteristic = "00000022-0000-1000-8000-0026BB765291"

    /// What the mapping needs to know about the characteristic besides the value.
    struct Context {
        var serviceType: String?
        var characteristicType: String
        /// Whether the characteristic's metadata says its format is Bool (`PowerState` is only a switch then).
        var isBoolFormat = false
        var minimumValue: Double?
        var maximumValue: Double?
        /// The values of the `Saturation` and `Brightness` characteristics of the same service, read for a colour.
        var saturation: Any?
        var brightness: Any?
    }

    /// Whether HomeKit has to be asked for the value of `type` on this characteristic at all: the service and
    /// format checks that come before the read. `false` leaves the item without a value, as before.
    static func needsRead(_ type: CharacteristicsType, context: Context) -> Bool {
        let service = context.serviceType
        switch type {
        case .motionSensor:
            return (service == occupancySensorService && context.characteristicType == occupancyDetectedCharacteristic)
                || (service == motionSensorService && context.characteristicType == motionDetectedCharacteristic)
        case .lightSensor:
            return service == lightSensorService
        case .switcher:
            return context.isBoolFormat
        case .contactSensor:
            return service == contactSensorService
        case .lock:
            return service == lockMechanismService
        case .batterySensor:
            return service == batteryService
        case .brightness, .colorTemperature, .color, .temperatureSensor, .relativeHumiditySensor, .carbonDioxideSensorId,
             .pmDensitySensor, .airQualitySensor, .targetTemperature, .heatingMode, .valvePosition,
             // classified from the service already (`HomeKitCharacteristic.toCharacteristicsType`)
             .heating, .valve:
            return true
        case .temperatureCalibration, .energyPrice, .deadline:
            // not a HomeKit characteristic
            return false
        }
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

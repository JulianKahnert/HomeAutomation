//
//  HeatingControlCharacteristic.swift
//  Adapter
//

import HAModels

/// The HomeKit characteristics that control a thermostat, matched by their HAP type UUID so the mapping
/// works and is testable without HomeKit.
///
/// A HAP-paired thermostat exposes the Thermostat service (`TargetTemperature`, `TargetHeatingCoolingState`).
/// A Matter-paired one, e.g. the Eve Thermo, exposes the HeaterCooler service instead
/// (`HeatingThresholdTemperature`, `TargetHeaterCoolerState`, and `Active`, which is stored as `.heating`).
enum HeatingControlCharacteristic {
    static let thermostatServiceUUID = "0000004A-0000-1000-8000-0026BB765291"
    static let heaterCoolerServiceUUID = "000000BC-0000-1000-8000-0026BB765291"

    static let targetTemperatureUUID = "00000035-0000-1000-8000-0026BB765291"
    static let targetHeatingCoolingStateUUID = "00000033-0000-1000-8000-0026BB765291"
    static let heatingThresholdTemperatureUUID = "00000012-0000-1000-8000-0026BB765291"
    static let targetHeaterCoolerStateUUID = "000000B2-0000-1000-8000-0026BB765291"

    private static let characteristicUUIDs: Set = [targetTemperatureUUID, targetHeatingCoolingStateUUID,
                                                   heatingThresholdTemperatureUUID, targetHeaterCoolerStateUUID]

    /// Whether a HomeKit characteristic type is one of the heating control characteristics, on any service.
    static func isHeatingControl(_ characteristicType: String) -> Bool {
        characteristicUUIDs.contains(characteristicType.uppercased())
    }

    /// Whether a HomeKit service type is a Thermostat or HeaterCooler service.
    static func isHeatingService(_ serviceType: String?) -> Bool {
        guard let serviceType = serviceType?.uppercased() else { return false }
        return serviceType == thermostatServiceUUID || serviceType == heaterCoolerServiceUUID
    }

    /// The stored type of a heating control characteristic, or `nil` when it sits on another service
    /// (a thermostat's heating threshold, for example, only applies in auto mode and is not stored).
    static func characteristicsType(characteristicType: String, serviceType: String?) -> CharacteristicsType? {
        switch (characteristicType.uppercased(), serviceType?.uppercased()) {
        case (targetTemperatureUUID, thermostatServiceUUID), (heatingThresholdTemperatureUUID, heaterCoolerServiceUUID):
            return .targetTemperature
        case (targetHeatingCoolingStateUUID, thermostatServiceUUID), (targetHeaterCoolerStateUUID, heaterCoolerServiceUUID):
            return .heatingMode
        default:
            return nil
        }
    }

    /// Converts the raw value of a mode characteristic, whose two HAP types number their states differently.
    ///
    /// `TargetHeatingCoolingState`: 0 off, 1 heat, 2 cool, 3 auto (the raw values of `HeatingMode`).
    /// `TargetHeaterCoolerState`: 0 auto, 1 heat, 2 cool; "off" is `Active = 0` there, stored as `.heating`.
    static func heatingMode(rawValue: Int, characteristicType: String) -> HeatingMode? {
        switch characteristicType.uppercased() {
        case targetHeatingCoolingStateUUID:
            return HeatingMode(rawValue: rawValue)
        case targetHeaterCoolerStateUUID:
            switch rawValue {
            case 0: return .auto
            case 1: return .heat
            case 2: return .cool
            default: return nil
            }
        default:
            return nil
        }
    }
}

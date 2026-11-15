//
//  CharacteristicsType.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 18.11.24.
//

public enum CharacteristicsType: String, Sendable, Codable, CaseIterable {
    case motionSensor, lightSensor, batterySensor, contactSensor
    case temperatureSensor, relativeHumiditySensor, carbonDioxideSensorId, pmDensitySensor, airQualitySensor
    case switcher, brightness, colorTemperature, color, valve
    case lock
    case heating
    /// Thermostat target temperature (HomeKit `TargetTemperature` or HeaterCooler `HeatingThresholdTemperature`),
    /// stored in `targetTemperatureInC`.
    case targetTemperature
    /// Thermostat target mode (HomeKit `TargetHeatingCoolingState` or `TargetHeaterCoolerState`), stored in `heatingMode`.
    case heatingMode
    /// Eve valve opening in percent, stored in `valvePositionPercent`.
    case valvePosition
}

public extension CharacteristicsType {
    /// Whether the adapter subscribes to HomeKit notifications for this type.
    ///
    /// Only subscribed types reach the server's history: the adapter yields them on every refresh and
    /// change, the others never. HomeKit drops notifications (contact sensors first) when there are too
    /// many subscriptions, so sensors that change often or matter little stay unsubscribed.
    var isSubscribed: Bool {
        switch self {
        case .motionSensor, .lightSensor, .switcher, .contactSensor, .carbonDioxideSensorId, .brightness, .colorTemperature, .color,
             .heating, .targetTemperature, .heatingMode, .valvePosition:
            return true
        case .batterySensor, .valve, .lock, .temperatureSensor, .relativeHumiditySensor, .pmDensitySensor, .airQualitySensor:
            return false
        }
    }

    /// Whether this type belongs to a thermostat (on/off, target temperature, mode, valve position).
    var isHeatingRelated: Bool {
        switch self {
        case .heating, .targetTemperature, .heatingMode, .valvePosition:
            return true
        default:
            return false
        }
    }
}

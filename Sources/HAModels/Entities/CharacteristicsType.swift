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
    /// Thermostat temperature offset in Celsius (Matter `LocalTemperatureCalibration`, the Eve app's
    /// "Temperaturabweichung"), stored in `temperatureCalibrationInC`.
    case temperatureCalibration
}

public extension CharacteristicsType {
    /// Whether the adapter subscribes to HomeKit notifications for this type.
    ///
    /// Only subscribed types reach the server's history: the adapter yields them on every refresh and
    /// change, the others never. HomeKit drops notifications (contact sensors first) when there are too
    /// many subscriptions, so sensors that change often or matter little stay unsubscribed.
    /// Temperature and humidity are subscribed: without it, a standalone room sensor (an air quality
    /// or temperature sensor) only reaches the history when another HomeKit client happens to read it.
    var isSubscribed: Bool {
        switch self {
        case .motionSensor, .lightSensor, .switcher, .contactSensor, .carbonDioxideSensorId, .brightness, .colorTemperature, .color,
             .temperatureSensor, .relativeHumiditySensor,
             .heating, .targetTemperature, .heatingMode, .valvePosition, .temperatureCalibration:
            return true
        case .batterySensor, .valve, .lock, .pmDensitySensor, .airQualitySensor:
            return false
        }
    }

    /// Whether this type belongs to a thermostat (on/off, target temperature, mode, valve position, temperature offset).
    var isHeatingRelated: Bool {
        switch self {
        case .heating, .targetTemperature, .heatingMode, .valvePosition, .temperatureCalibration:
            return true
        default:
            return false
        }
    }
}

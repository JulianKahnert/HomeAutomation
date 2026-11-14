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
    /// Thermostat target temperature, stored in `targetTemperatureInC`.
    case targetTemperature
    /// Thermostat target mode (HomeKit `TargetHeatingCoolingState`), stored in `heatingMode`.
    case heatingMode
    /// Eve valve opening in percent, stored in `valvePositionPercent`.
    case valvePosition
}

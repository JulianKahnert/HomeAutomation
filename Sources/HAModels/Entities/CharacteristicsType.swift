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
    /// Electricity price in EUR per kWh, read through `energyPriceInEURPerKWh`.
    case energyPrice
    /// A server-owned deadline (a window's Fensterschließzeit, the fireplace question): none, running until a moment or
    /// overdue, read through `deadline`.
    case deadline
}

public extension CharacteristicsType {
    /// Whether the adapter subscribes to HomeKit notifications for this type.
    ///
    /// HomeKit drops notifications (contact sensors first) when there are too many subscriptions, so sensors
    /// that change often or matter little stay unsubscribed. A type reaches the server's history when it is
    /// subscribed or polled, see ``isReported``.
    /// Temperature and humidity are subscribed: without it, a standalone room sensor (an air quality
    /// or temperature sensor) only reaches the history when another HomeKit client happens to read it.
    var isSubscribed: Bool {
        switch self {
        case .motionSensor, .lightSensor, .switcher, .contactSensor, .carbonDioxideSensorId, .brightness, .colorTemperature, .color,
             .temperatureSensor, .relativeHumiditySensor,
             .heating, .targetTemperature, .heatingMode, .valvePosition, .temperatureCalibration:
            return true
        case .energyPrice:
            return false
        case .batterySensor, .valve, .lock, .pmDensitySensor, .airQualitySensor, .deadline:
            return false
        }
    }

    /// Whether the adapter reads this type actively, on every full resync and every ``pollInterval``, instead of
    /// relying on notifications: HomeKit notifications are unreliable for some standalone sensors, and the battery
    /// level is not subscribed at all. The poll is additional to the subscription of temperature and humidity.
    var isPolled: Bool {
        switch self {
        case .batterySensor, .temperatureSensor, .relativeHumiditySensor:
            return true
        default:
            return false
        }
    }

    /// Whether the adapter sends reads of this type to the server (a resync yields them): subscribed or polled types.
    var isReported: Bool {
        isSubscribed || isPolled
    }

    /// The period of the adapter's poll of all ``isPolled`` types.
    static var pollInterval: Duration { .seconds(3 * 3600) }

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

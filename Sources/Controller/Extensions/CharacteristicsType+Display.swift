//
//  CharacteristicsType+Display.swift
//  Controller
//
//  Display name extensions for CharacteristicsType
//

import Foundation
import HAModels

extension CharacteristicsType {
    /// Human-readable display name for the characteristic type
    public var displayName: String {
        switch self {
        case .motionSensor:
            return "Motion Sensor"
        case .lightSensor:
            return "Light Sensor"
        case .batterySensor:
            return "Battery Sensor"
        case .contactSensor:
            return "Contact Sensor"
        case .temperatureSensor:
            return "Temperature Sensor"
        case .relativeHumiditySensor:
            return "Humidity Sensor"
        case .carbonDioxideSensorId:
            return "CO₂ Sensor"
        case .pmDensitySensor:
            return "PM Density Sensor"
        case .airQualitySensor:
            return "Air Quality Sensor"
        case .switcher:
            return "Switch"
        case .brightness:
            return "Brightness"
        case .colorTemperature:
            return "Color Temperature"
        case .color:
            return "Color"
        case .valve:
            return "Valve"
        case .lock:
            return "Lock"
        case .heating:
            return "Heating"
        }
    }

    var systemImage: String {
        switch self {
        case .motionSensor: return "figure.walk"
        case .lightSensor: return "sun.max"
        case .batterySensor: return "battery.75percent"
        case .contactSensor: return "window.casement"
        case .temperatureSensor: return "thermometer.medium"
        case .relativeHumiditySensor: return "humidity"
        case .carbonDioxideSensorId: return "carbon.dioxide.cloud"
        case .pmDensitySensor, .airQualitySensor: return "aqi.medium"
        case .switcher: return "lightbulb"
        case .brightness: return "light.max"
        case .colorTemperature: return "thermometer.sun"
        case .color: return "paintpalette"
        case .valve: return "spigot"
        case .lock: return "lock"
        case .heating: return "heater.vertical"
        }
    }
}

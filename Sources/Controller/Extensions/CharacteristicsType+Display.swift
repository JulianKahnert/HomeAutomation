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
}

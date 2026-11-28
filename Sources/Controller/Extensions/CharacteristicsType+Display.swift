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
            return String(localized: "Motion Sensor", bundle: .module)
        case .lightSensor:
            return String(localized: "Light Sensor", bundle: .module)
        case .batterySensor:
            return String(localized: "Battery Sensor", bundle: .module)
        case .contactSensor:
            return String(localized: "Contact Sensor", bundle: .module)
        case .temperatureSensor:
            return String(localized: "Temperature Sensor", bundle: .module)
        case .relativeHumiditySensor:
            return String(localized: "Humidity Sensor", bundle: .module)
        case .carbonDioxideSensorId:
            return String(localized: "CO₂ Sensor", bundle: .module)
        case .pmDensitySensor:
            return String(localized: "PM Density Sensor", bundle: .module)
        case .airQualitySensor:
            return String(localized: "Air Quality Sensor", bundle: .module)
        case .switcher:
            return String(localized: "Switch", bundle: .module)
        case .brightness:
            return String(localized: "Brightness", bundle: .module)
        case .colorTemperature:
            return String(localized: "Color Temperature", bundle: .module)
        case .color:
            return String(localized: "Color", bundle: .module)
        case .valve:
            return String(localized: "Valve", bundle: .module)
        case .lock:
            return String(localized: "Lock", bundle: .module)
        case .heating:
            return String(localized: "Heating", bundle: .module)
        case .targetTemperature:
            return String(localized: "Target Temperature", bundle: .module)
        case .heatingMode:
            return String(localized: "Heating Mode", bundle: .module)
        case .valvePosition:
            return String(localized: "Valve Position", bundle: .module)
        case .temperatureCalibration:
            return String(localized: "Temperature Offset", bundle: .module)
        case .energyPrice:
            return String(localized: "Electricity price", bundle: .module)
        case .deadline:
            return String(localized: "Deadline", bundle: .module)
        }
    }

}

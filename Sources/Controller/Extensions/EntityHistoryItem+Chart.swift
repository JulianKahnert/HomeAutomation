//
//  EntityHistoryItem+Chart.swift
//  Controller
//
//  Chart visualization extensions for EntityHistoryItem
//

import Foundation
import HAModels
import SwiftUI

extension EntityHistoryItem {
    /// Returns a SwiftUI Color from RGB values if available
    public var color: Color? {
        guard let r = colorRed,
              let g = colorGreen,
              let b = colorBlue else {
            return nil
        }
        return Color(red: Double(r), green: Double(g), blue: Double(b))
    }

    /// Returns the hue (color tone) in degrees (0-360°) from RGB values
    /// Uses the existing RGB.hue helper from HAModels
    private var hue: Double? {
        guard let r = colorRed,
              let g = colorGreen,
              let b = colorBlue else {
            return nil
        }
        let rgb = RGB(red: r, green: g, blue: b)
        return Double(rgb.hue)
    }

    /// Returns the primary value for this history item based on available data
    /// Used for chart visualization
    /// Priority order: numeric sensors > percentage sensors > boolean sensors > color (hue)
    public var primaryValue: Double? {
        // Temperature (high priority - common sensor)
        if let temperatureInC {
            return temperatureInC
        }
        // Humidity (high priority - common sensor)
        if let relativeHumidity {
            return relativeHumidity
        }
        // CO2 (high priority - important air quality metric)
        if let carbonDioxideSensorId {
            return Double(carbonDioxideSensorId)
        }
        // Air quality index
        if let airQuality {
            return Double(airQuality)
        }
        // PM density (particulate matter)
        if let pmDensity {
            return pmDensity
        }
        // Illuminance
        if let illuminanceInLux {
            return illuminanceInLux
        }
        // Brightness percentage
        if let brightness {
            return Double(brightness)
        }
        // Battery state of charge
        if let stateOfCharge {
            return Double(stateOfCharge)
        }
        // Color temperature
        if let colorTemperature {
            return Double(colorTemperature)
        }
        // Boolean sensors (lower priority)
        if let isDeviceOn {
            return isDeviceOn ? 1.0 : 0.0
        }
        if let motionDetected {
            return motionDetected ? 1.0 : 0.0
        }
        if let isContactOpen {
            return isContactOpen ? 1.0 : 0.0
        }
        if let isDoorLocked {
            return isDoorLocked ? 1.0 : 0.0
        }
        if let isHeaterActive {
            return isHeaterActive ? 1.0 : 0.0
        }
        if let valveOpen {
            return valveOpen ? 1.0 : 0.0
        }
        // Color as hue (last priority)
        if let hue {
            return hue
        }
        return nil
    }

    /// Human-readable description of the primary value
    public var valueDescription: String {
        if let temperatureInC {
            return "\(String(format: "%.1f", temperatureInC))°C"
        }
        if let relativeHumidity {
            return "\(String(format: "%.1f", relativeHumidity))%"
        }
        if let carbonDioxideSensorId {
            return "\(carbonDioxideSensorId) ppm"
        }
        if let airQuality {
            return "AQI: \(airQuality)"
        }
        if let pmDensity {
            return "\(String(format: "%.1f", pmDensity)) µg/m³"
        }
        if let illuminanceInLux {
            return "\(String(format: "%.1f", illuminanceInLux)) lux"
        }
        if let brightness {
            return "\(brightness)%"
        }
        if let stateOfCharge {
            return "\(stateOfCharge)%"
        }
        if let colorTemperature {
            return "CT: \(String(format: "%.2f", colorTemperature))"
        }
        if let isDeviceOn {
            return isDeviceOn ? "On" : "Off"
        }
        if let motionDetected {
            return motionDetected ? "Motion" : "No Motion"
        }
        if let isContactOpen {
            return isContactOpen ? "Open" : "Closed"
        }
        if let isDoorLocked {
            return isDoorLocked ? "Locked" : "Unlocked"
        }
        if let isHeaterActive {
            return isHeaterActive ? "Active" : "Inactive"
        }
        if let valveOpen {
            return valveOpen ? "Open" : "Closed"
        }
        // Color as hue
        if let hue {
            return "\(String(format: "%.0f", hue))° hue"
        }
        return "No data"
    }
}

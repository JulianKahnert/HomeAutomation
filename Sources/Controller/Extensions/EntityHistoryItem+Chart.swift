//
//  EntityHistoryItem+Chart.swift
//  Controller
//
//  Chart visualization extensions for EntityHistoryItem
//

import Foundation
import HAModels

extension EntityHistoryItem {
    /// Returns the primary value for this history item based on available data
    /// Used for chart visualization
    public var primaryValue: Double? {
        if let illuminanceInLux {
            return illuminanceInLux
        }
        if let stateOfCharge {
            return Double(stateOfCharge)
        }
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
        return nil
    }

    /// Human-readable description of the primary value
    public var valueDescription: String {
        if let illuminanceInLux {
            return "\(String(format: "%.1f", illuminanceInLux)) lux"
        }
        if let stateOfCharge {
            return "\(stateOfCharge)%"
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
        return "No data"
    }
}

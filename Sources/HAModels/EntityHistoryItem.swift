//
//  EntityHistoryItem.swift
//  HAModels
//
//  Created for entity history visualization feature
//

import Foundation

/// Represents a single historical data point for an entity
public struct EntityHistoryItem: Identifiable, Sendable, Codable, Equatable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let motionDetected: Bool?
    public let illuminanceInLux: Double?
    public let isDeviceOn: Bool?
    public let brightness: Int?
    public let colorTemperature: Float?
    public let colorRed: Float?
    public let colorGreen: Float?
    public let colorBlue: Float?
    public let isContactOpen: Bool?
    public let isDoorLocked: Bool?
    public let stateOfCharge: Int?
    public let isHeaterActive: Bool?
    public let temperatureInC: Double?
    public let relativeHumidity: Double?
    public let carbonDioxideSensorId: Int?
    public let pmDensity: Double?
    public let airQuality: Int?
    public let valveOpen: Bool?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        motionDetected: Bool? = nil,
        illuminanceInLux: Double? = nil,
        isDeviceOn: Bool? = nil,
        brightness: Int? = nil,
        colorTemperature: Float? = nil,
        colorRed: Float? = nil,
        colorGreen: Float? = nil,
        colorBlue: Float? = nil,
        isContactOpen: Bool? = nil,
        isDoorLocked: Bool? = nil,
        stateOfCharge: Int? = nil,
        isHeaterActive: Bool? = nil,
        temperatureInC: Double? = nil,
        relativeHumidity: Double? = nil,
        carbonDioxideSensorId: Int? = nil,
        pmDensity: Double? = nil,
        airQuality: Int? = nil,
        valveOpen: Bool? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.motionDetected = motionDetected
        self.illuminanceInLux = illuminanceInLux
        self.isDeviceOn = isDeviceOn
        self.brightness = brightness
        self.colorTemperature = colorTemperature
        self.colorRed = colorRed
        self.colorGreen = colorGreen
        self.colorBlue = colorBlue
        self.isContactOpen = isContactOpen
        self.isDoorLocked = isDoorLocked
        self.stateOfCharge = stateOfCharge
        self.isHeaterActive = isHeaterActive
        self.temperatureInC = temperatureInC
        self.relativeHumidity = relativeHumidity
        self.carbonDioxideSensorId = carbonDioxideSensorId
        self.pmDensity = pmDensity
        self.airQuality = airQuality
        self.valveOpen = valveOpen
    }
}

extension EntityHistoryItem {
    public init(_ item: EntityStorageItem) {
        self.init(timestamp: item.timestamp,
                  motionDetected: item.motionDetected,
                  illuminanceInLux: item.illuminance?.value,
                  isDeviceOn: item.isDeviceOn,
                  brightness: item.brightness,
                  colorTemperature: item.colorTemperature,
                  colorRed: item.color?.red,
                  colorGreen: item.color?.green,
                  colorBlue: item.color?.blue,
                  isContactOpen: item.isContactOpen,
                  isDoorLocked: item.isDoorLocked,
                  stateOfCharge: item.stateOfCharge,
                  isHeaterActive: item.isHeaterActive,
                  temperatureInC: item.temperatureInC?.value,
                  relativeHumidity: item.relativeHumidity,
                  carbonDioxideSensorId: item.carbonDioxideSensorId,
                  pmDensity: item.pmDensity,
                  airQuality: item.airQuality,
                  valveOpen: item.valveOpen)
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
        if let colorRed, let colorGreen, let colorBlue {
            let hue = Double(RGB(red: colorRed, green: colorGreen, blue: colorBlue).hue)
            return "\(String(format: "%.0f", hue))° hue"
        }
        return "No data"
    }
}

/// Response wrapper for paginated entity history
public struct EntityHistoryResponse: Sendable, Codable, Equatable {
    public let items: [EntityHistoryItem]
    public let nextCursor: Date?

    public init(items: [EntityHistoryItem], nextCursor: Date?) {
        self.items = items
        self.nextCursor = nextCursor
    }

    public var hasMore: Bool {
        nextCursor != nil
    }
}

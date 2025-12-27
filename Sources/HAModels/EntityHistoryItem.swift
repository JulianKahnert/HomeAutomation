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

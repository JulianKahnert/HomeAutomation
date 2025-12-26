//
//  EntityStorageItem.swift
//  
//
//  Created by Julian Kahnert on 04.07.24.
//

import Foundation

/// Storage item representing the state of a home automation entity at a specific point in time
public struct EntityStorageItem: Equatable, Sendable, Codable, CustomStringConvertible, Hashable {
    /// Unique identifier for the entity
    public let entityId: EntityId

    /// Timestamp when this state was recorded
    public var timestamp: Date

    /// Motion detection state (true if motion detected)
    public let motionDetected: Bool?

    let _illuminanceInLux: Double?
    /// Light level measurement in lux
    public var illuminance: Measurement<UnitIlluminance>? {
        guard let _illuminanceInLux else { return nil }
        return Measurement(value: _illuminanceInLux, unit: .lux)
    }

    /// Device power state (true if on, false if off)
    public let isDeviceOn: Bool?

    /// Light brightness level (0-100)
    public let brightness: Int?

    /// Color temperature in mireds
    public let colorTemperature: Int?

    /// RGB color value
    public let color: RGB?

    /// Contact sensor state (true if open, false if closed)
    public let isContactOpen: Bool?

    /// Door lock state (true if locked, false if unlocked)
    public let isDoorLocked: Bool?

    /// Battery state of charge percentage (0-100)
    public let stateOfCharge: Int?

    /// Heater active state (true if heating)
    public let isHeaterActive: Bool?

    let _temperatureInC: Double?
    /// Temperature measurement in Celsius
    public var temperatureInC: Measurement<UnitTemperature>? {
        guard let _temperatureInC else { return nil }
        return Measurement(value: _temperatureInC, unit: .celsius)
    }

    /// Relative humidity percentage (0-100)
    public let relativeHumidity: Double?

    /// Carbon dioxide level in ppm
    public let carbonDioxideSensorId: Int?

    /// Particulate matter density (PM2.5/PM10)
    public let pmDensity: Double?

    /// Air quality index
    public let airQuality: Int?

    /// Valve open state (true if open)
    public let valveOpen: Bool?

    public var description: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "EntityStorageItem(entityId: \(entityId))"
        }
        return string
    }

    /// Creates a new entity storage item with all available properties
    public init(
        entityId: EntityId,
        timestamp: Date = Date(),
        motionDetected: Bool? = nil,
        illuminance: Measurement<UnitIlluminance>? = nil,
        isDeviceOn: Bool? = nil,
        brightness: Int? = nil,
        colorTemperature: Int? = nil,
        color: RGB? = nil,
        isContactOpen: Bool? = nil,
        isDoorLocked: Bool? = nil,
        stateOfCharge: Int? = nil,
        isHeaterActive: Bool? = nil,
        temperatureInC: Measurement<UnitTemperature>? = nil,
        relativeHumidity: Double? = nil,
        carbonDioxideSensorId: Int? = nil,
        pmDensity: Double? = nil,
        airQuality: Int? = nil,
        valveOpen: Bool? = nil
    ) {
        self.entityId = entityId
        self.timestamp = timestamp
        self.motionDetected = motionDetected
        self._illuminanceInLux = illuminance?.converted(to: .lux).value
        self.isDeviceOn = isDeviceOn
        self.brightness = brightness
        self.colorTemperature = colorTemperature
        self.color = color
        self.isContactOpen = isContactOpen
        self.isDoorLocked = isDoorLocked
        self.stateOfCharge = stateOfCharge
        self.isHeaterActive = isHeaterActive
        self._temperatureInC = temperatureInC?.converted(to: .celsius).value
        self.relativeHumidity = relativeHumidity
        self.carbonDioxideSensorId = carbonDioxideSensorId
        self.pmDensity = pmDensity
        self.airQuality = airQuality
        self.valveOpen = valveOpen
    }

    /// Retrieves a non-optional value for a given optional property key path
    /// - Parameter path: Key path to an optional property
    /// - Returns: The unwrapped value
    /// - Throws: `EntityStorageError.notFound` if the property is nil
    public func get<T>(_ path: KeyPath<Self, T?>) throws(EntityStorageError) -> T {
        let value = self[keyPath: path]
        guard let value else { throw EntityStorageError.notFound }
        return value
    }
}

public enum EntityStorageError: Error {
    case notFound
}

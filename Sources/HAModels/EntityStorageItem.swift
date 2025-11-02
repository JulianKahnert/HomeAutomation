//
//  EntityStorageItem.swift
//  
//
//  Created by Julian Kahnert on 04.07.24.
//

import Foundation

public enum EntityStorageItemType: String, CaseIterable {
    case motion, illuminance, isDeviceOn, isContactOpen, isDoorLocked, stateOfCharge, isHeaterActive
}

public struct EntityStorageItem: Equatable, Sendable, Codable, CustomStringConvertible, Hashable {
    public let entityId: EntityId
    public var timestamp: Date

    public let motionDetected: Bool?
    let _illuminanceInLux: Double?
    public var illuminance: Measurement<UnitIlluminance>? {
        guard let _illuminanceInLux else { return nil }
        return Measurement(value: _illuminanceInLux, unit: .lux)
    }
    public let isDeviceOn: Bool?
    public let isContactOpen: Bool?
    public let isDoorLocked: Bool?
    public let stateOfCharge: Int?
    public let isHeaterActive: Bool?

    public var description: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "EntityStorageItem(entityId: \(entityId))"
        }
        return string
    }

    public init(entityId: EntityId) {
        self.entityId = entityId
        self.timestamp = Date()
        self.motionDetected = nil
        self._illuminanceInLux = nil
        self.isDeviceOn = nil
        self.isContactOpen = nil
        self.isDoorLocked = nil
        self.stateOfCharge = nil
        self.isHeaterActive = nil
    }

    public init(entityId: EntityId, timestamp: Date, motionDetected: Bool?, illuminance: Measurement<UnitIlluminance>?, isDeviceOn: Bool?, isContactOpen: Bool?, isDoorLocked: Bool?, stateOfCharge: Int?, isHeaterActive: Bool?) {
        self.entityId = entityId
        self.timestamp = timestamp
        self.motionDetected = motionDetected
        self._illuminanceInLux = illuminance?.converted(to: .lux).value
        self.isDeviceOn = isDeviceOn
        self.isContactOpen = isContactOpen
        self.isDoorLocked = isDoorLocked
        self.stateOfCharge = stateOfCharge
        self.isHeaterActive = isHeaterActive
    }

    public func get<T>(_ path: KeyPath<Self, T?>) throws -> T {
        let value = self[keyPath: path]
        guard let value else { throw EntityStorageError.notFound }
        return value
    }
}

public enum EntityStorageError: Error {
    case notFound
}

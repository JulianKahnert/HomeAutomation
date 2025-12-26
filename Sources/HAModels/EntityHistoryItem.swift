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
    public let isContactOpen: Bool?
    public let isDoorLocked: Bool?
    public let stateOfCharge: Int?
    public let isHeaterActive: Bool?

    public init(
        id: UUID = UUID(),
        timestamp: Date,
        motionDetected: Bool? = nil,
        illuminanceInLux: Double? = nil,
        isDeviceOn: Bool? = nil,
        isContactOpen: Bool? = nil,
        isDoorLocked: Bool? = nil,
        stateOfCharge: Int? = nil,
        isHeaterActive: Bool? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.motionDetected = motionDetected
        self.illuminanceInLux = illuminanceInLux
        self.isDeviceOn = isDeviceOn
        self.isContactOpen = isContactOpen
        self.isDoorLocked = isDoorLocked
        self.stateOfCharge = stateOfCharge
        self.isHeaterActive = isHeaterActive
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

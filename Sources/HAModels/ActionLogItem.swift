//
//  ActionLogItem.swift
//
//
//  Created by Julian Kahnert on 14.11.25.
//

import Foundation

public struct ActionLogItem: Identifiable, Sendable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let entityId: EntityId
    public let actionName: String
    public let detailDescription: String
    public let hasCacheHit: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        action: HomeManagableAction,
        hasCacheHit: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.entityId = action.entityId
        self.actionName = action.actionName
        self.detailDescription = action.description
        self.hasCacheHit = hasCacheHit
    }

    public init(id: UUID, timestamp: Date, entityId: EntityId, actionName: String, detailDescription: String, hasCacheHit: Bool) {
        self.id = id
        self.timestamp = timestamp
        self.entityId = entityId
        self.actionName = actionName
        self.detailDescription = detailDescription
        self.hasCacheHit = hasCacheHit
    }

    /// Human-readable description for display
    public var displayName: String {
        "\(actionName) - \(entityId)"
    }

    /// Searchable text combining all relevant fields
    public var searchableText: String {
        "\(actionName) \(entityId) \(detailDescription)"
            .localizedLowercase
    }
}

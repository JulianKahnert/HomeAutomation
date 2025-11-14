//
//  ActionLogItem.swift
//
//
//  Created by Julian Kahnert on 14.11.25.
//

import Foundation

public struct ActionLogItem: Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let action: HomeManagableAction
    public let hasCacheHit: Bool

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        action: HomeManagableAction,
        hasCacheHit: Bool
    ) {
        self.id = id
        self.timestamp = timestamp
        self.action = action
        self.hasCacheHit = hasCacheHit
    }

    /// Human-readable description for display
    public var displayName: String {
        "\(action.actionName) - \(action.entityId)"
    }

    /// Detailed description with all parameters
    public var detailDescription: String {
        action.description
    }

    /// Searchable text combining all relevant fields
    public var searchableText: String {
        "\(action.actionName) \(action.entityId) \(detailDescription)"
            .localizedLowercase
    }
}

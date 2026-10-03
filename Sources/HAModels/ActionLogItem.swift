//
//  ActionLogItem.swift
//
//
//  Created by Julian Kahnert on 14.11.25.
//

import Foundation

public struct ActionLogItem: Identifiable, Sendable, Codable, Equatable {
    public enum Status: String, Sendable, Codable, CaseIterable {
        /// Sent to the adapter.
        case executed
        /// Skipped as a duplicate of a recently executed command.
        case cacheHit
        /// The adapter call threw.
        case failed
    }

    public let id: UUID
    public let timestamp: Date
    public let entityId: EntityId
    public let actionName: String
    public let detailDescription: String
    public let hasCacheHit: Bool
    /// The `AutomationRun` that sent the command; `nil` for API calls and older servers.
    public let runId: UUID?
    /// `nil` from servers that predate it.
    public var status: Status?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        action: HomeManagableAction,
        hasCacheHit: Bool,
        runId: UUID? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.entityId = action.entityId
        self.actionName = action.actionName
        self.detailDescription = action.description
        self.hasCacheHit = hasCacheHit
        self.runId = runId
        self.status = hasCacheHit ? .cacheHit : .executed
    }

    public init(id: UUID, timestamp: Date, entityId: EntityId, actionName: String, detailDescription: String, hasCacheHit: Bool, runId: UUID? = nil, status: Status? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.entityId = entityId
        self.actionName = actionName
        self.detailDescription = detailDescription
        self.hasCacheHit = hasCacheHit
        self.runId = runId
        self.status = status
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

//
//  EntityInfo.swift
//  HAModels
//
//  Created for entity history visualization feature
//

import Foundation

/// Represents a unique entity with metadata
public struct EntityInfo: Identifiable, Sendable, Codable, Equatable, Hashable {
    public let id: String
    public let entityId: EntityId

    public init(id: String, entityId: EntityId) {
        self.id = id
        self.entityId = entityId
    }

    public init(entityId: EntityId) {
        self.entityId = entityId
        self.id = "\(entityId.placeId)_\(entityId.name)_\(entityId.characteristicType.rawValue)"
    }

    #if DEBUG
    /// Creates a placeholder entity for preview/testing
    public static func preview(
        placeId: String = "living-room",
        name: String = "Light",
        type: CharacteristicsType = .switcher
    ) -> EntityInfo {
        EntityInfo(
            entityId: EntityId(
                placeId: placeId,
                name: name,
                characteristicsName: nil,
                characteristic: type
            )
        )
    }
    #endif
}

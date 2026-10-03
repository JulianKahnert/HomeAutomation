//
//  EntityInfo+Display.swift
//  Controller
//
//  Display extensions for EntityInfo
//

import Foundation
import HAModels

extension EntityInfo {
    /// Human-readable display name for the entity
    public var displayName: String {
        entityId.displayName
    }

    /// Formatted characteristic display name using the CharacteristicsType extension
    public var formattedCharacteristicDisplayName: String {
        entityId.characteristicType.displayName
    }
}

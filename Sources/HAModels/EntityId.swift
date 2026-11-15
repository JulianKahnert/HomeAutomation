//
//  EntityId.swift
//  
//
//  Created by Julian Kahnert on 03.07.24.
//

import Foundation

public struct EntityId: Sendable, Hashable, Equatable, Codable, CustomStringConvertible {
    public let placeId: PlaceId
    public let name: String
    public let characteristicsName: String?
    public let characteristicType: CharacteristicsType

    public init(placeId: PlaceId, name: String, characteristicsName: String?, characteristic: CharacteristicsType) {
        self.placeId = placeId
        self.name = name
        self.characteristicsName = characteristicsName
        self.characteristicType = characteristic
    }

    public init(query: EntityId.Query, characteristic: CharacteristicsType) {
        self.placeId = query.placeId
        self.name = query.name
        self.characteristicsName = query.characteristicsName
        self.characteristicType = characteristic
    }

    public var description: String {
        "[\(placeId) - \(name)]: \(characteristicType.rawValue)"
    }

    public static func == (lhs: EntityId, rhs: EntityId) -> Bool {
        if let lhsCharacteristicsName = lhs.characteristicsName,
           let rhsCharacteristicsName = rhs.characteristicsName {
            return lhs.placeId == rhs.placeId && lhs.name == rhs.name && lhsCharacteristicsName == rhsCharacteristicsName && lhs.characteristicType == rhs.characteristicType
        } else {
            return lhs.placeId == rhs.placeId && lhs.name == rhs.name && lhs.characteristicType == rhs.characteristicType
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(placeId)
        hasher.combine(name)
        // we skip the characteristicsName, since it might not be set manually and should be skipped in comparisons
        hasher.combine(characteristicType)
    }
}

extension EntityId {
    public struct Query: Sendable, CustomStringConvertible {
        public let placeId: PlaceId
        public let name: String
        public let characteristicsName: String?

        public init(placeId: PlaceId, name: String, characteristicsName: String? = nil) {
            self.placeId = placeId
            self.name = name
            self.characteristicsName = characteristicsName
        }

        public var description: String {
            "[\(placeId) - \(name) \(characteristicsName ?? "")]"
        }
    }
}

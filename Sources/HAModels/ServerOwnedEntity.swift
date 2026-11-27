//
//  ServerOwnedEntity.swift
//  HAModels
//

import Foundation

public extension EntityId {
    /// The place of every server-owned entity (glossary): a state the server keeps itself, not HomeKit.
    static let serverOwnedPlaceId: PlaceId = "server"

    /// A server-owned entity named `name`; its value kind is `characteristic`.
    static func serverOwned(name: String, characteristic: CharacteristicsType) -> EntityId {
        EntityId(placeId: serverOwnedPlaceId, name: name, characteristicsName: nil, characteristic: characteristic)
    }

    /// Whether the server keeps this entity itself. `POST /config` accepts it without HomeKit knowing it (ADR-009).
    var isServerOwned: Bool { placeId == Self.serverOwnedPlaceId }
}

//
//  AppSettableEntities.swift
//  HAModels
//

import Foundation

/// The server-owned entities the app may set through `PUT /entities/state`, declared one by one.
///
/// It is a list of entities, not of value kinds: a computed state (the plan target of a room) shares its kind
/// with a state the user sets, and the app must not overwrite it. A later ticket adds its entity here.
public enum AppSettableEntities {
    public static let all: Set<EntityId> = [
        .serverOwned(name: "fireplace", characteristic: .switcher)
    ]

    public static func contains(_ entityId: EntityId) -> Bool {
        entityId.isServerOwned && all.contains(entityId)
    }
}

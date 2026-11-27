//
//  EntityStorageItem.swift
//  
//
//  Created by Julian Kahnert on 04.07.24.
//

import Foundation

/// Storage item representing the state of a home automation entity at a specific point in time
public struct EntityStorageItem: Equatable, Sendable, Codable, CustomStringConvertible, Hashable {
    /// Unique identifier for the entity
    public let entityId: EntityId

    /// Timestamp when this state was recorded
    public var timestamp: Date

    /// What kind of value the item carries; `nil` for an item without a value.
    public let kind: ValueKind?

    /// The one value of the item; its shape follows ``kind``. The typed accessors (`temperatureInC`, `isDeviceOn`, ...)
    /// are derived from the pair, see `EntityStorageItem+TypedAccess.swift`.
    public let value: Value?

    /// Where this change came from. It is no part of the value: two items that differ only in
    /// timestamp and origin carry the same information (see `HomeManager.addEntityHistory`).
    public var origin: Origin

    /// When the entity last reported, a replay included; `timestamp` stays the time of the last change.
    /// Memory only: never stored, `nil` after a restart until the first report. Like `origin` it is no part of
    /// the value (see `HomeManager.addEntityHistory`).
    public var lastReport: Date?

    public var description: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "EntityStorageItem(entityId: \(entityId))"
        }
        return string
    }

    /// Creates an item from its kind and value as they are, without checking that they fit; the checked
    /// way in is ``init(entityId:timestamp:kind:value:origin:)`` (failable).
    init(entityId: EntityId, timestamp: Date, uncheckedKind kind: ValueKind?, value: Value?, origin: Origin, lastReport: Date? = nil) {
        self.entityId = entityId
        self.timestamp = timestamp
        self.kind = kind
        self.value = value
        self.origin = origin
        self.lastReport = lastReport
    }

    /// Creates an item without a value, such as a report that only says the entity is alive.
    public init(entityId: EntityId, timestamp: Date = Date(), origin: Origin = .homekit, lastReport: Date? = nil) {
        self.init(entityId: entityId, timestamp: timestamp, uncheckedKind: nil, value: nil, origin: origin, lastReport: lastReport)
    }

    /// Retrieves a non-optional value for a given optional property key path
    /// - Parameter path: Key path to an optional property
    /// - Returns: The unwrapped value
    /// - Throws: `EntityStorageError.notFound` if the property is nil
    public func get<T>(_ path: KeyPath<Self, T?>) throws(EntityStorageError) -> T {
        let value = self[keyPath: path]
        guard let value else { throw EntityStorageError.notFound }
        return value
    }
}

public enum EntityStorageError: Error {
    case notFound
}

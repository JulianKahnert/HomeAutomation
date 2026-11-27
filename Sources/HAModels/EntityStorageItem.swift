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

    /// The one value of the item; its shape follows the characteristic type of ``entityId``, the one table is
    /// ``ValueDescriptor/descriptor(for:)``. The typed accessors (`temperatureInC`, `isDeviceOn`, ...)
    /// are derived from it, see `EntityStorageItem+TypedAccess.swift`.
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

    /// What kind of value the item carries, the characteristic type of its entity; `nil` for an item without a value.
    public var kind: CharacteristicsType? {
        value == nil ? nil : entityId.characteristicType
    }

    /// Creates an item from its value as it is, without checking that it fits; the checked way in is
    /// ``init(entityId:timestamp:value:origin:)`` (failable).
    init(entityId: EntityId, timestamp: Date, uncheckedValue value: Value?, origin: Origin, lastReport: Date? = nil) {
        self.entityId = entityId
        self.timestamp = timestamp
        self.value = value
        self.origin = origin
        self.lastReport = lastReport
    }

    /// Creates an item without a value, such as a report that only says the entity is alive.
    public init(entityId: EntityId, timestamp: Date = Date(), origin: Origin = .homekit, lastReport: Date? = nil) {
        self.init(entityId: entityId, timestamp: timestamp, uncheckedValue: nil, origin: origin, lastReport: lastReport)
    }

    /// Whether `other` carries the same information: same entity and value. Timestamp, origin and `lastReport`
    /// are no part of the value, so every field added later stays out of this compare.
    public func hasSameValue(as other: Self) -> Bool {
        entityId == other.entityId && value == other.value
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

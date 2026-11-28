//
//  EntityStorageItem+Wire.swift
//  HAModels
//

import Foundation

public extension EntityStorageItem {
    /// Creates an item from its value; `nil` when the value does not fit the kind of the entity: the wrong
    /// shape, a fraction for a whole-number kind, a heating mode that does not exist, a colour that is not "r g b" or a deadline that does not parse.
    init?(entityId: EntityId, timestamp: Date = Date(), value: Value, origin: Origin = .homekit) {
        guard ValueDescriptor.descriptor(for: entityId.characteristicType).accepts(value) else { return nil }
        self.init(entityId: entityId, timestamp: timestamp, uncheckedValue: value, origin: origin)
    }
}

/// The wire form (protocol version 3): entity, timestamp, value kind, one value and origin. The typed fields
/// do not cross the wire; `lastReport` is memory only and stays off it.
extension EntityStorageItem {
    private enum WireKeys: String, CodingKey {
        case entityId, timestamp, kind, value, origin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: WireKeys.self)
        let entityId = try container.decode(EntityId.self, forKey: .entityId)
        let timestamp = try container.decode(Date.self, forKey: .timestamp)
        let origin = try container.decodeIfPresent(Origin.self, forKey: .origin) ?? .homekit
        guard let kind = try container.decodeIfPresent(String.self, forKey: .kind) else {
            self.init(entityId: entityId, timestamp: timestamp, origin: origin)
            return
        }
        // The kind is the characteristic type of the entity; the wire still names it, so the formats stay one.
        guard kind == entityId.characteristicType.rawValue else {
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "The value kind \(kind) is not the kind of the entity")
        }
        let value = try container.decode(Value.self, forKey: .value)
        guard let item = EntityStorageItem(entityId: entityId, timestamp: timestamp, value: value, origin: origin) else {
            throw DecodingError.dataCorruptedError(forKey: .value, in: container, debugDescription: "Value does not fit the value kind \(kind)")
        }
        self = item
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: WireKeys.self)
        try container.encode(entityId, forKey: .entityId)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(origin, forKey: .origin)
        if let value {
            try container.encode(entityId.characteristicType.rawValue, forKey: .kind)
            try container.encode(value, forKey: .value)
        }
    }
}

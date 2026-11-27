//
//  EntityStorageItem+GenericValue.swift
//  HAModels
//

import Foundation

/// The generic form of a state: its value kind and one value. It is what the item stores; the typed accessors
/// derive from it.
public extension EntityStorageItem {
    /// Kind and value, `nil` for an item without a value.
    var genericValue: (kind: ValueKind, value: Value)? {
        guard let kind, let value else { return nil }
        return (kind, value)
    }

    /// Creates an item from kind and value; `nil` when the kind is unknown or the value does not fit it: the wrong
    /// shape, a fraction for a whole-number kind, a heating mode that does not exist, a colour that is not "r g b" or a deadline that does not parse.
    init?(entityId: EntityId, timestamp: Date = Date(), kind: ValueKind, value: Value, origin: Origin = .homekit) {
        guard let descriptor = kind.descriptor, descriptor.accepts(value) else { return nil }
        self.init(entityId: entityId, timestamp: timestamp, uncheckedKind: kind, value: value, origin: origin)
    }

    /// The value when the item carries the kind of `type`, `nil` otherwise.
    func value(of type: CharacteristicsType) -> Value? {
        kind == type.valueKind ? value : nil
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
        guard let kind = try container.decodeIfPresent(ValueKind.self, forKey: .kind) else {
            self.init(entityId: entityId, timestamp: timestamp, origin: origin)
            return
        }
        let value = try container.decode(Value.self, forKey: .value)
        guard let item = EntityStorageItem(entityId: entityId, timestamp: timestamp, kind: kind, value: value, origin: origin) else {
            throw DecodingError.dataCorruptedError(forKey: .value, in: container, debugDescription: "Value does not fit the value kind \(kind.rawValue)")
        }
        self = item
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: WireKeys.self)
        try container.encode(entityId, forKey: .entityId)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(origin, forKey: .origin)
        if let generic = genericValue {
            try container.encode(generic.kind, forKey: .kind)
            try container.encode(generic.value, forKey: .value)
        }
    }
}

//
//  EntityDbItem.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAModels

/// The directory of entities: one row per place, service and characteristic type. The changes of an
/// entity reference it, so a change row carries no entity strings.
final class EntityDbItem: Model, @unchecked Sendable {
    static let schema = "entities"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "placeId")
    var placeId: String

    @Field(key: "serviceName")
    var serviceName: String

    @Field(key: "characteristicType")
    var characteristicType: String

    /// The newest name seen for the entity.
    @Field(key: "characteristicsName")
    var characteristicsName: String?

    init() { }

    init(placeId: String, serviceName: String, characteristicType: String, characteristicsName: String?) {
        self.placeId = placeId
        self.serviceName = serviceName
        self.characteristicType = characteristicType
        self.characteristicsName = characteristicsName
    }
}

/// One change of one entity: a number or a text, plus where it came from. A Bool is stored as 1 or 0.
final class EntityChangeDbItem: Model, @unchecked Sendable {
    static let schema = "entityChanges"

    @ID(key: .id)
    var id: UUID?

    @Parent(key: "entityId")
    var entity: EntityDbItem

    @Field(key: "timestamp")
    var timestamp: Date

    @Field(key: "number")
    var number: Double?

    @Field(key: "text")
    var text: String?

    @Field(key: "origin")
    var origin: String

    init() { }

    init(entityId: UUID, timestamp: Date, value: Value, origin: String) {
        self.$entity.id = entityId
        self.timestamp = timestamp
        self.origin = origin
        self.number = nil
        self.text = nil
        switch value {
        case .bool(let flag): number = flag ? 1 : 0
        case .number(let double): number = double
        case .text(let string): text = string
        }
    }

    /// The value in the shape of the kind's descriptor, `nil` when the column of that shape is empty.
    func value(shape: ValueDescriptor.Shape) -> Value? {
        switch shape {
        case .bool: number.map { .bool($0 != 0) }
        case .number: number.map { .number($0) }
        case .text: text.map { .text($0) }
        }
    }
}

extension EntityStorageItem {
    /// The typed form of a stored change. A value the typed form cannot hold (a future HAP heating mode)
    /// leaves the item without a value instead of failing the row.
    init?(entity: EntityDbItem, change: EntityChangeDbItem) {
        guard let type = CharacteristicsType(rawValue: entity.characteristicType) else { return nil }
        let entityId = EntityId(placeId: entity.placeId, name: entity.serviceName,
                                characteristicsName: entity.characteristicsName, characteristic: type)
        let origin = Origin(rawValue: change.origin)
        let shape = ValueDescriptor.descriptor(for: type).shape
        if let value = change.value(shape: shape),
           let item = EntityStorageItem(entityId: entityId, timestamp: change.timestamp, kind: type.valueKind, value: value, origin: origin) {
            self = item
        } else {
            self = EntityStorageItem(entityId: entityId, timestamp: change.timestamp, origin: origin)
        }
    }
}

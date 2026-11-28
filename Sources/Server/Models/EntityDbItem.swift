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

    /// When the entity last reported, an unchanged report included: written with each change and otherwise at most
    /// every five minutes. `nil` for an entity that has not reported since this column exists.
    @OptionalField(key: "lastReport")
    var lastReport: Date?

    init() { }

    init(placeId: String, serviceName: String, characteristicType: String, characteristicsName: String?) {
        self.placeId = placeId
        self.serviceName = serviceName
        self.characteristicType = characteristicType
        self.characteristicsName = characteristicsName
        self.lastReport = nil
    }
}

/// One change of one entity: a number or a text, plus where it came from. A Bool is stored as 1 or 0.
final class EntityChangeDbItem: Model, @unchecked Sendable {
    static let schema = "entityChanges"

    /// A database-generated BIGINT: rows append at the end of the clustered index, and equal timestamps order by write.
    @ID(custom: .id, generatedBy: .database)
    var id: Int?

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

    /// The width of the `text` column.
    static let textLimit = 255

    init() { }

    /// - Parameter shape: The shape of the kind's descriptor; only `textWithNumber` (a deadline) splits its text.
    init(entityId: UUID, timestamp: Date, value: Value, shape: ValueDescriptor.Shape = .text, origin: String) {
        self.$entity.id = entityId
        self.timestamp = timestamp
        self.origin = origin
        self.number = nil
        self.text = nil
        switch value {
        case .bool(let flag): number = flag ? 1 : 0
        case .number(let double): number = double
        case .text(let string):
            // A deadline keeps its case in the text and its end in the number, in one row.
            if shape == .textWithNumber, let deadline = Deadline(text: string) {
                text = deadline.caseName
                number = deadline.end?.timeIntervalSince1970
            } else {
                text = string.fitted(toScalars: Self.textLimit)
            }
        }
    }

    /// The value in the shape of the kind's descriptor, `nil` when the column of that shape is empty.
    func value(shape: ValueDescriptor.Shape) -> Value? {
        switch shape {
        case .bool:
            return number.map { .bool($0 != 0) }
        case .number:
            return number.map { .number($0) }
        case .text:
            return text.map { .text($0) }
        case .textWithNumber:
            return text.flatMap { Deadline(caseName: $0, end: number) }.map { .text($0.text) }
        }
    }
}

extension EntityStorageItem {
    /// The typed form of a stored change. A value the typed form cannot hold (a future HAP heating mode)
    /// leaves the item without a value instead of failing the row.
    /// - Parameter withLastReport: Whether the item carries the entity's time of the last report: the later of
    ///   `entities.lastReport` and the change's own timestamp. That time belongs to the newest change only, so only the
    ///   readers of the current state set it.
    init?(entity: EntityDbItem, change: EntityChangeDbItem, withLastReport: Bool = false) {
        guard let type = CharacteristicsType(rawValue: entity.characteristicType) else { return nil }
        let entityId = EntityId(placeId: entity.placeId, name: entity.serviceName,
                                characteristicsName: entity.characteristicsName, characteristic: type)
        let origin = Origin(rawValue: change.origin)
        let shape = ValueDescriptor.descriptor(for: type).shape
        // The stored time of the last report is throttled, so a newer change counts through its own timestamp.
        let lastReport = withLastReport ? max(entity.lastReport ?? change.timestamp, change.timestamp) : nil
        if let value = change.value(shape: shape), let item = EntityStorageItem(entityId: entityId, timestamp: change.timestamp, value: value, origin: origin) {
            self = item
        } else {
            self = EntityStorageItem(entityId: entityId, timestamp: change.timestamp, origin: origin)
        }
        self.lastReport = lastReport
    }
}

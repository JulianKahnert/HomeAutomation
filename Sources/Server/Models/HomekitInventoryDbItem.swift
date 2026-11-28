//
//  HomekitInventoryDbItem.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAModels

/// One characteristic of the HomeKit inventory, see `HomeKitInventoryItem`. The table is replaced as a whole with
/// each snapshot of the adapter; `syncedAt` is the time of that snapshot. Text columns are fitted to their width.
final class HomekitInventoryDbItem: Model, @unchecked Sendable {
    static let schema = "homekitInventory"

    @ID(custom: .id, generatedBy: .database)
    var id: Int64?

    @Field(key: "homeName")
    var homeName: String

    @Field(key: "roomName")
    var roomName: String

    @Field(key: "accessoryName")
    var accessoryName: String

    @OptionalField(key: "manufacturer")
    var manufacturer: String?

    @OptionalField(key: "model")
    var model: String?

    @Field(key: "serviceType")
    var serviceType: String

    @Field(key: "serviceName")
    var serviceName: String

    @Field(key: "characteristicType")
    var characteristicType: String

    @Field(key: "characteristicDescription")
    var characteristicDescription: String

    /// The raw value of our `CharacteristicsType`, `NULL` when the characteristic is not mapped.
    @OptionalField(key: "mappedType")
    var mappedType: String?

    @Field(key: "isReadable")
    var isReadable: Bool

    @Field(key: "isNotifiable")
    var isNotifiable: Bool

    @Field(key: "isWritable")
    var isWritable: Bool

    @OptionalField(key: "value")
    var value: String?

    @Field(key: "syncedAt")
    var syncedAt: Date

    init() {}

    init(_ item: HomeKitInventoryItem, syncedAt: Date) {
        homeName = item.homeName.fitted(toScalars: Self.nameWidth)
        roomName = item.roomName.fitted(toScalars: Self.nameWidth)
        accessoryName = item.accessoryName.fitted(toScalars: Self.nameWidth)
        manufacturer = item.manufacturer?.fitted(toScalars: Self.nameWidth)
        model = item.model?.fitted(toScalars: Self.nameWidth)
        serviceType = item.serviceType.fitted(toScalars: Self.typeWidth)
        serviceName = item.serviceName.fitted(toScalars: Self.nameWidth)
        characteristicType = item.characteristicType.fitted(toScalars: Self.typeWidth)
        characteristicDescription = item.characteristicDescription.fitted(toScalars: Self.nameWidth)
        mappedType = item.mappedType?.rawValue
        isReadable = item.isReadable
        isNotifiable = item.isNotifiable
        isWritable = item.isWritable
        value = item.value?.fitted(toScalars: Self.valueWidth)
        self.syncedAt = syncedAt
    }

    /// The widths of the columns (`.string` is VARCHAR(255)).
    static let nameWidth = 255
    static let typeWidth = 64
    static let valueWidth = 255
}

//
//  HomekitInventoryDbItem.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAModels

/// One characteristic of the HomeKit inventory, see `HomeKitInventory`. The table is replaced as a whole with
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

    @Field(key: "accessoryCategory")
    var accessoryCategory: String

    @Field(key: "isReachable")
    var isReachable: Bool

    @OptionalField(key: "manufacturer")
    var manufacturer: String?

    @OptionalField(key: "model")
    var model: String?

    @Field(key: "serviceType")
    var serviceType: String

    @Field(key: "serviceTypeDescription")
    var serviceTypeDescription: String

    @Field(key: "serviceName")
    var serviceName: String

    @Field(key: "isPrimaryService")
    var isPrimaryService: Bool

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

    init(_ row: HomeKitInventory.Row, syncedAt: Date) {
        homeName = row.homeName.fitted(toScalars: Self.nameWidth)
        roomName = row.roomName.fitted(toScalars: Self.nameWidth)
        accessoryName = row.accessory.name.fitted(toScalars: Self.nameWidth)
        accessoryCategory = row.accessory.category.fitted(toScalars: Self.nameWidth)
        isReachable = row.accessory.isReachable
        manufacturer = row.accessory.manufacturer?.fitted(toScalars: Self.nameWidth)
        model = row.accessory.model?.fitted(toScalars: Self.nameWidth)
        serviceType = row.service.type.fitted(toScalars: Self.typeWidth)
        serviceTypeDescription = row.service.typeDescription.fitted(toScalars: Self.nameWidth)
        serviceName = row.service.name.fitted(toScalars: Self.nameWidth)
        isPrimaryService = row.service.isPrimary
        characteristicType = row.characteristic.type.fitted(toScalars: Self.typeWidth)
        characteristicDescription = row.characteristic.typeDescription.fitted(toScalars: Self.nameWidth)
        mappedType = row.characteristic.mappedType?.rawValue
        isReadable = row.characteristic.isReadable
        isNotifiable = row.characteristic.isNotifiable
        isWritable = row.characteristic.isWritable
        value = row.characteristic.value?.fitted(toScalars: Self.valueWidth)
        self.syncedAt = syncedAt
    }

    /// The widths of the columns (`.string` is VARCHAR(255)).
    static let nameWidth = 255
    static let typeWidth = 64
    static let valueWidth = 255
}

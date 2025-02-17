//
//  EntityStorageDbItem.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 06.02.25.
//

import Fluent
import Foundation
import HAModels

/// Property wrappers interact poorly with `Sendable` checking, causing a warning for the `@ID` property
/// It is recommended you write your model with sendability checking on and then suppress the warning
/// afterwards with `@unchecked Sendable`.
final class EntityStorageDbItem: Model, @unchecked Sendable {
    static let schema = "entityItems"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "timestamp")
    var timestamp: Date

    @Field(key: "entityPlaceId")
    var entityPlaceId: String

    @Field(key: "entityServiceName")
    var entityServiceName: String

    @Field(key: "entityCharacteristicsName")
    var entityCharacteristicsName: String?

    @Field(key: "entityCharacteristicType")
    var entityCharacteristicType: String

    @Field(key: "motionDetected")
    var motionDetected: Bool?

    @Field(key: "illuminanceInLux")
    var illuminanceInLux: Double?

    @Field(key: "isDeviceOn")
    var isDeviceOn: Bool?

    @Field(key: "isContactOpen")
    var isContactOpen: Bool?

    @Field(key: "isDoorLocked")
    var isDoorLocked: Bool?

    @Field(key: "stateOfCharge")
    var stateOfCharge: Int?

    @Field(key: "isHeaterActive")
    var isHeaterActive: Bool?

    init() { }

    init(timestamp: Date, entityPlaceId: String, entityServiceName: String, entityCharacteristicsName: String? = nil, entityCharacteristicType: String, motionDetected: Bool? = nil, illuminanceInLux: Double? = nil, isDeviceOn: Bool? = nil, isContactOpen: Bool? = nil, isDoorLocked: Bool? = nil, stateOfCharge: Int? = nil, isHeaterActive: Bool? = nil) {
        self.timestamp = timestamp
        self.entityPlaceId = entityPlaceId
        self.entityServiceName = entityServiceName
        self.entityCharacteristicsName = entityCharacteristicsName
        self.entityCharacteristicType = entityCharacteristicType
        self.motionDetected = motionDetected
        self.illuminanceInLux = illuminanceInLux
        self.isDeviceOn = isDeviceOn
        self.isContactOpen = isContactOpen
        self.isDoorLocked = isDoorLocked
        self.stateOfCharge = stateOfCharge
        self.isHeaterActive = isHeaterActive
    }

    private static func mapDbItem(_ item: EntityStorageDbItem) -> EntityStorageItem {
        var illuminance: Measurement<UnitIlluminance>?
        if let illuminanceInLux = item.illuminanceInLux {
            illuminance = .init(value: illuminanceInLux, unit: .lux)
        }
        let entityId = EntityId(placeId: item.entityPlaceId,
                                name: item.entityServiceName,
                                characteristicsName: item.entityCharacteristicsName,
                                characteristic: CharacteristicsType(rawValue: item.entityCharacteristicType) ?? .batterySensor)
        return EntityStorageItem(entityId: entityId,
                                 timestamp: item.timestamp,
                                 motionDetected: item.motionDetected,
                                 illuminance: illuminance,
                                 isDeviceOn: item.isDeviceOn,
                                 isContactOpen: item.isContactOpen,
                                 isDoorLocked: item.isDoorLocked,
                                 stateOfCharge: item.stateOfCharge,
                                 isHeaterActive: item.isHeaterActive)
    }

    private static func map(_ item: EntityStorageItem) -> EntityStorageDbItem {
        return EntityStorageDbItem(timestamp: item.timestamp,
                                   entityPlaceId: item.entityId.placeId,
                                   entityServiceName: item.entityId.name,
                                   entityCharacteristicsName: item.entityId.characteristicsName,
                                   entityCharacteristicType: item.entityId.characteristicType.rawValue,
                                   motionDetected: item.motionDetected,
                                   illuminanceInLux: item.illuminance?.converted(to: .lux).value,
                                   isDeviceOn: item.isDeviceOn,
                                   isContactOpen: item.isContactOpen,
                                   isDoorLocked: item.isDoorLocked,
                                   stateOfCharge: item.stateOfCharge,
                                   isHeaterActive: item.isHeaterActive)
    }
}

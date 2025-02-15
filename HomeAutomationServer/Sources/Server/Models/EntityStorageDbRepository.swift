//
//  EntityStorageDbRepository.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 06.02.25.
//

import Fluent
import Foundation
import HAModels

final class EntityStorageDbRepository: StorageRepository, @unchecked Sendable {
    let database: any Database

    init(database: any Database) {
        self.database = database
    }

    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem? {
        try await EntityStorageDbItem
            .query(on: database)
            .filter(\.$entityPlaceId == entityId.placeId)
            .filter(\.$entityServiceName == entityId.name)
            .filter(\.$entityCharacteristicType == entityId.characteristicType.rawValue)
            .sort(\.$timestamp, .descending)
            .all()
            .filter { item in
                guard let lhs = item.entityCharacteristicsName,
                      let rhs = entityId.characteristicsName else { return true }
                return lhs == rhs
            }
            .first
            .map(Self.mapDbItem)
    }

    func getPrevious(_ entityId: EntityId) async throws -> EntityStorageItem? {
        let items = try await EntityStorageDbItem
            .query(on: database)
            .filter(\.$entityPlaceId == entityId.placeId)
            .filter(\.$entityServiceName == entityId.name)
            .filter(\.$entityCharacteristicsName == entityId.characteristicsName)
            .filter(\.$entityCharacteristicType == entityId.characteristicType.rawValue)
            .sort(\.$timestamp, .descending)
            .all()
            .lazy
            .prefix(2)

        guard items.count == 2 else {
            return nil
        }
        return items.last
            .map(Self.mapDbItem)
    }

    func add(_ item: EntityStorageItem) async throws {
        try await Self.map(item).save(on: database)
    }

    func deleteEntries(olderThan date: Date) async throws {
        try await EntityStorageDbItem.query(on: database)
            .filter(\.$timestamp < date)
            .delete()
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

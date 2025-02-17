//
//  SwiftDataStorageRepository.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 23.07.24.
//

#if canImport(SwiftData)
import Foundation
import HAModels
import Logging
import SwiftData

public actor SwiftDataStorageRepository: StorageRepository, ModelActor {

    private static let log = Logger(label: "SwiftDataStorageRepository")

    // https://useyourloaf.com/blog/swiftdata-background-tasks/
    public let modelContainer: ModelContainer
    public let modelExecutor: any ModelExecutor

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        // "Apple warns you not to use the model executor to access the model context. Instead you should use the modelContext property of the actor."
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        Self.log.trace("[SwiftDataStorageRepository] init called")
    }

    public func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem? {
        let placeId = entityId.placeId
        let name = entityId.name
        let characteristicType = entityId.characteristicType.rawValue
        let predicate = #Predicate<TimestampEntityStorageItem> { item in
            item.entityPlaceId == placeId && item.entityServiceName == name && item.entityCharacteristicType == characteristicType
        }
        var descriptor = FetchDescriptor<TimestampEntityStorageItem>(
            predicate: predicate,
            sortBy: [SortDescriptor(\TimestampEntityStorageItem.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let items = try modelContext.fetch(descriptor)
        guard let item = items.first else { return nil }
        return Self.mapDbItem(item)
    }

    public func getPrevious(_ entityId: EntityId) async throws -> EntityStorageItem? {
        let placeId = entityId.placeId
        let name = entityId.name
        let characteristicType = entityId.characteristicType.rawValue
        let predicate = #Predicate<TimestampEntityStorageItem> { item in
            item.entityPlaceId == placeId && item.entityServiceName == name && item.entityCharacteristicType == characteristicType
        }
        var descriptor = FetchDescriptor<TimestampEntityStorageItem>(
            predicate: predicate,
            sortBy: [SortDescriptor(\TimestampEntityStorageItem.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 2
        let items = try modelContext.fetch(descriptor)
        guard items.count == 2,
              let item = items.last else { return nil }
        return Self.mapDbItem(item)
    }

    public func add(_ item: EntityStorageItem) async throws {
        let dbItem = Self.map(item)
        modelContext.insert(dbItem)
        try modelContext.save()
    }

    public func deleteEntries(olderThan date: Date) async throws {
        try modelContext.delete(model: TimestampEntityStorageItem.self, where: #Predicate {
            $0.timestamp < date
        })
        try modelContext.save()
    }

    private static func mapDbItem(_ item: TimestampEntityStorageItem) -> EntityStorageItem {
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

    private static func map(_ item: EntityStorageItem) -> TimestampEntityStorageItem {
        return TimestampEntityStorageItem(timestamp: item.timestamp,
                                          entityPlaceId: item.entityId.placeId,
                                          entityName: item.entityId.name,
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
#endif

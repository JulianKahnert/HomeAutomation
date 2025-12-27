//
//  EntityStorageDbRepository.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 06.02.25.
//

import Fluent
import Foundation
import HAModels
import Logging
import SQLKit
import Vapor

final class EntityStorageDbRepository: StorageRepository, @unchecked Sendable {
    let database: any Database
    private let log = Logger(label: "EntityStorageDbRepository")

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
            .filter(\.$entityCharacteristicType == entityId.characteristicType.rawValue)
            .sort(\.$timestamp, .descending)
            .all()
            .filter { item in
                guard let lhs = item.entityCharacteristicsName,
                      let rhs = entityId.characteristicsName else { return true }
                return lhs == rhs
            }
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

    func getHistory(
        for entityId: EntityId,
        startDate: Date?,
        endDate: Date?,
        cursor: Date?,
        limit: Int
    ) async throws -> [EntityStorageItem] {
        var query = EntityStorageDbItem
            .query(on: database)
            .filter(\.$entityPlaceId == entityId.placeId)
            .filter(\.$entityServiceName == entityId.name)
            .filter(\.$entityCharacteristicType == entityId.characteristicType.rawValue)

        // Apply time range filters
        if let startDate {
            query = query.filter(\.$timestamp >= startDate)
        }
        if let endDate {
            query = query.filter(\.$timestamp < endDate)
        }

        // Apply cursor-based pagination (fetch items older than cursor)
        if let cursor {
            query = query.filter(\.$timestamp < cursor)
        }

        // Order by timestamp descending and apply limit
        let items = try await query
            .sort(\.$timestamp, .descending)
            .limit(limit)
            .all()

        // Filter by characteristicsName if present (must be done in-memory due to optional field)
        let filteredItems = items.filter { item in
            guard let lhs = item.entityCharacteristicsName,
                  let rhs = entityId.characteristicsName else { return true }
            return lhs == rhs
        }

        return filteredItems.map(Self.mapDbItem)
    }

    func getAllEntityIds() async throws -> [EntityId] {
        guard let sqlDatabase = database as? SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL queries")
        }

        // Use raw SQL DISTINCT for optimal performance with large datasets
        let rows = try await sqlDatabase.raw("""
            SELECT DISTINCT
                \(ident: "entityPlaceId"),
                \(ident: "entityServiceName"),
                \(ident: "entityCharacteristicsName"),
                \(ident: "entityCharacteristicType")
            FROM \(ident: EntityStorageDbItem.schema)
            """)
            .all()

        return rows.compactMap { row -> EntityId? in
            guard let placeId = try? row.decode(column: "entityPlaceId", as: String.self),
                  let serviceName = try? row.decode(column: "entityServiceName", as: String.self),
                  let characteristicTypeRaw = try? row.decode(column: "entityCharacteristicType", as: String.self),
                  let characteristicType = CharacteristicsType(rawValue: characteristicTypeRaw) else {
                log.error("Failed to decode entity ID from database row")
                assertionFailure("Failed to decode entity ID from database row")
                return nil
            }

            let characteristicsName = try? row.decode(column: "entityCharacteristicsName", as: String?.self)

            return EntityId(
                placeId: placeId,
                name: serviceName,
                characteristicsName: characteristicsName,
                characteristic: characteristicType
            )
        }
    }

    private static func mapDbItem(_ item: EntityStorageDbItem) -> EntityStorageItem {
        var illuminance: Measurement<UnitIlluminance>?
        if let illuminanceInLux = item.illuminanceInLux {
            illuminance = .init(value: illuminanceInLux, unit: .lux)
        }

        var temperatureInC: Measurement<UnitTemperature>?
        if let tempC = item.temperatureInC {
            temperatureInC = .init(value: tempC, unit: .celsius)
        }

        var color: RGB?
        if let red = item.colorRed, let green = item.colorGreen, let blue = item.colorBlue {
            color = RGB(red: red, green: green, blue: blue)
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
                                 brightness: item.brightness,
                                 colorTemperature: item.colorTemperature,
                                 color: color,
                                 isContactOpen: item.isContactOpen,
                                 isDoorLocked: item.isDoorLocked,
                                 stateOfCharge: item.stateOfCharge,
                                 isHeaterActive: item.isHeaterActive,
                                 temperatureInC: temperatureInC,
                                 relativeHumidity: item.relativeHumidity,
                                 carbonDioxideSensorId: item.carbonDioxideSensorId,
                                 pmDensity: item.pmDensity,
                                 airQuality: item.airQuality,
                                 valveOpen: item.valveOpen)
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
                                   isHeaterActive: item.isHeaterActive,
                                   brightness: item.brightness,
                                   colorTemperature: item.colorTemperature,
                                   colorRed: item.color?.red,
                                   colorGreen: item.color?.green,
                                   colorBlue: item.color?.blue,
                                   temperatureInC: item.temperatureInC?.converted(to: .celsius).value,
                                   relativeHumidity: item.relativeHumidity,
                                   carbonDioxideSensorId: item.carbonDioxideSensorId,
                                   pmDensity: item.pmDensity,
                                   airQuality: item.airQuality,
                                   valveOpen: item.valveOpen)
    }
}

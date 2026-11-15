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
    /// Resolved per query: a captured `app.db` is bound to one event loop and so to that loop's
    /// connection pool, which would funnel every query of this long-lived repository through it.
    let database: @Sendable () -> any Database
    private let log = Logger(label: "EntityStorageDbRepository")

    init(database: @escaping @Sendable () -> any Database) {
        self.database = database
    }

    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem? {
        try await latestItems(of: entityId, limit: 1)
            .first
            .map(Self.mapDbItem)
    }

    func getPrevious(_ entityId: EntityId) async throws -> EntityStorageItem? {
        let items = try await latestItems(of: entityId, limit: 2)
        guard items.count == 2 else {
            return nil
        }
        return items.last
            .map(Self.mapDbItem)
    }

    /// The newest `limit` rows of an entity. Filters and limits in SQL, so a lookup reads a few
    /// entries of `idx_entityItems_entity_timestamp` instead of loading the entity's whole history.
    /// A row without `entityCharacteristicsName` matches any name, as before.
    private func latestItems(of entityId: EntityId, limit: Int) async throws -> [EntityStorageDbItem] {
        try await itemsQuery(of: entityId)
            .sort(\.$timestamp, .descending)
            .limit(limit)
            .all()
    }

    /// All rows of an entity. A row without `entityCharacteristicsName`, or an `entityId` without
    /// one, matches any name.
    private func itemsQuery(of entityId: EntityId) -> QueryBuilder<EntityStorageDbItem> {
        let query = EntityStorageDbItem
            .query(on: database())
            .filter(\.$entityPlaceId == entityId.placeId)
            .filter(\.$entityServiceName == entityId.name)
            .filter(\.$entityCharacteristicType == entityId.characteristicType.rawValue)
        guard let characteristicsName = entityId.characteristicsName else {
            return query
        }
        return query.group(.or) { group in
            group.filter(\.$entityCharacteristicsName == nil)
                .filter(\.$entityCharacteristicsName == characteristicsName)
        }
    }

    func add(_ item: EntityStorageItem) async throws {
        let dbItem = Self.map(item)
        guard try await passesDeadBand(dbItem, of: item.entityId) else { return }
        try await dbItem.save(on: database())
        if item.entityId.characteristicType.isHeatingRelated {
            log.debug("Stored heating entity item", metadata: [
                "entityId": "\(item.entityId)",
                "isHeaterActive": "\(item.isHeaterActive.map { "\($0)" } ?? "nil")",
                "targetTemperatureInC": "\(item.targetTemperatureInC.map { "\($0)" } ?? "nil")",
                "heatingMode": "\(item.heatingMode?.name ?? "nil")",
                "valvePositionPercent": "\(item.valvePositionPercent.map { "\($0)" } ?? "nil")"
            ])
        }
    }

    /// Whether `item` moved out of its type's write dead band (`StoragePolicy`) around the last
    /// stored row. Types without a dead band cost no extra query.
    private func passesDeadBand(_ item: EntityStorageDbItem, of entityId: EntityId) async throws -> Bool {
        let policy = StoragePolicy.policy(for: entityId.characteristicType)
        guard let deadBand = policy.deadBand, let column = policy.valueColumn, let value = column.value(in: item) else {
            return true
        }
        let lastStored = try await latestItems(of: entityId, limit: 1).first.flatMap { row in
            column.value(in: row).map { (value: $0, timestamp: row.timestamp) }
        }
        return deadBand.shouldStore(value, at: item.timestamp, lastStored: lastStored)
    }

    /// The rollup rows of an entity, oldest hour first.
    func hourlyAggregates(of entityId: EntityId) async throws -> [EntityHourlyAggregate] {
        let rows = try await sqlDatabase().raw("""
            SELECT * FROM \(ident: EntityHourlyAggregate.schema)
            WHERE \(ident: "entityPlaceId") = \(bind: entityId.placeId)
              AND \(ident: "entityServiceName") = \(bind: entityId.name)
              AND \(ident: "entityCharacteristicType") = \(bind: entityId.characteristicType.rawValue)
            ORDER BY \(ident: "hourStart")
            """)
            .all()
        return try rows.map { row in
            try EntityHourlyAggregate(entityId: entityId,
                                      hourStart: row.decode(column: "hourStart", as: Date.self),
                                      minValue: row.decode(column: "minValue", as: Double.self),
                                      meanValue: row.decode(column: "meanValue", as: Double.self),
                                      maxValue: row.decode(column: "maxValue", as: Double.self),
                                      lastValue: row.decode(column: "lastValue", as: Double.self),
                                      valueCount: row.decode(column: "valueCount", as: Int.self))
        }
    }

    private func sqlDatabase() throws -> any SQLDatabase {
        guard let sqlDatabase = database() as? SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL queries")
        }
        return sqlDatabase
    }

    func getHistory(
        for entityId: EntityId,
        startDate: Date?,
        endDate: Date?,
        cursor: Date?,
        limit: Int
    ) async throws -> [EntityStorageItem] {
        var query = itemsQuery(of: entityId)

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

        // Order by timestamp descending and apply limit; the characteristicsName filter is part of
        // the query, so a page is never cut short after the limit.
        return try await query
            .sort(\.$timestamp, .descending)
            .limit(limit)
            .all()
            .map(Self.mapDbItem)
    }

    func getAllEntityIds() async throws -> [EntityId] {
        let sqlDatabase = try sqlDatabase()

        // DISTINCT over the three indexed columns lets MySQL use a covering index skip scan
        // (`idx_entityItems_entity_timestamp`) instead of scanning the whole table. The name comes from
        // the newest row of each entity, one index lookup per entity.
        let rows = try await sqlDatabase.raw("""
            SELECT
                d.\(ident: "entityPlaceId"),
                d.\(ident: "entityServiceName"),
                d.\(ident: "entityCharacteristicType"),
                (SELECT n.\(ident: "entityCharacteristicsName")
                 FROM \(ident: EntityStorageDbItem.schema) n
                 WHERE n.\(ident: "entityPlaceId") = d.\(ident: "entityPlaceId")
                   AND n.\(ident: "entityServiceName") = d.\(ident: "entityServiceName")
                   AND n.\(ident: "entityCharacteristicType") = d.\(ident: "entityCharacteristicType")
                 ORDER BY n.\(ident: "timestamp") DESC
                 LIMIT 1) AS \(ident: "entityCharacteristicsName")
            FROM (
                SELECT DISTINCT \(ident: "entityPlaceId"), \(ident: "entityServiceName"), \(ident: "entityCharacteristicType")
                FROM \(ident: EntityStorageDbItem.schema)
            ) d
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

    /// An unknown raw value (a future HAP mode) becomes `nil` instead of failing the whole row.
    private static func heatingMode(of item: EntityStorageDbItem) -> HeatingMode? {
        guard let raw = item.heatingMode else { return nil }
        guard let mode = HeatingMode(rawValue: raw) else {
            Logger(label: "EntityStorageDbRepository").warning("Unknown heatingMode \(raw) in entityItems, read as nil")
            return nil
        }
        return mode
    }

    static func mapDbItem(_ item: EntityStorageDbItem) -> EntityStorageItem {
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
                                 valveOpen: item.valveOpen,
                                 targetTemperatureInC: item.targetTemperatureInC,
                                 heatingMode: heatingMode(of: item),
                                 valvePositionPercent: item.valvePositionPercent)
    }

    static func map(_ item: EntityStorageItem) -> EntityStorageDbItem {
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
                                   valveOpen: item.valveOpen,
                                   targetTemperatureInC: item.targetTemperatureInC,
                                   heatingMode: item.heatingMode?.rawValue,
                                   valvePositionPercent: item.valvePositionPercent)
    }
}

extension EntityStorageDbRepository: EntityRetentionStore {
    func deleteEntries(ofType type: CharacteristicsType, olderThan date: Date) async throws {
        try await sqlDatabase().raw("""
            DELETE FROM \(ident: EntityStorageDbItem.schema)
            WHERE \(ident: "entityCharacteristicType") = \(bind: type.rawValue) AND \(ident: "timestamp") < \(bind: date)
            """)
            .run()
    }

    func rollUpHourly(type: CharacteristicsType, column: StoragePolicy.ValueColumn, validRange: ClosedRange<Double>?, olderThan date: Date) async throws {
        let range = validRange ?? -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude
        try await database().transaction { database in
            guard let sql = database as? SQLDatabase else {
                throw Abort(.internalServerError, reason: "Database does not support SQL queries")
            }
            // An hour that already has a row (a late raw row) is merged; the update order matters
            // because MySQL assigns left to right, so the mean reads the old count. `maxValue` is a
            // reserved word, hence the backticks.
            try await sql.raw("""
                INSERT INTO \(ident: EntityHourlyAggregate.schema)
                    (entityPlaceId, entityServiceName, entityCharacteristicType, hourStart, `minValue`, `meanValue`, `maxValue`, `lastValue`, `valueCount`)
                SELECT * FROM (
                    SELECT entityPlaceId, entityServiceName, entityCharacteristicType, hourStart,
                           MIN(v) AS minV, AVG(v) AS meanV, MAX(v) AS maxV, MAX(CASE WHEN rn = 1 THEN v END) AS lastV, COUNT(*) AS countV
                    FROM (
                        SELECT entityPlaceId, entityServiceName, entityCharacteristicType,
                               TIMESTAMP(DATE_FORMAT(\(ident: "timestamp"), '%Y-%m-%d %H:00:00')) AS hourStart,
                               \(ident: column.rawValue) AS v,
                               ROW_NUMBER() OVER (PARTITION BY entityPlaceId, entityServiceName, entityCharacteristicType,
                                                               DATE_FORMAT(\(ident: "timestamp"), '%Y-%m-%d %H')
                                                  ORDER BY \(ident: "timestamp") DESC) AS rn
                        FROM \(ident: EntityStorageDbItem.schema)
                        WHERE entityCharacteristicType = \(bind: type.rawValue)
                          AND \(ident: "timestamp") < \(bind: date)
                          AND \(ident: column.rawValue) BETWEEN \(bind: range.lowerBound) AND \(bind: range.upperBound)
                    ) raw
                    GROUP BY entityPlaceId, entityServiceName, entityCharacteristicType, hourStart
                ) AS hourly
                ON DUPLICATE KEY UPDATE
                    `minValue` = LEAST(`minValue`, hourly.minV),
                    `maxValue` = GREATEST(`maxValue`, hourly.maxV),
                    `meanValue` = (`meanValue` * `valueCount` + hourly.meanV * hourly.countV) / (`valueCount` + hourly.countV),
                    `lastValue` = hourly.lastV,
                    `valueCount` = `valueCount` + hourly.countV
                """)
                .run()
            try await sql.raw("""
                DELETE FROM \(ident: EntityStorageDbItem.schema)
                WHERE \(ident: "entityCharacteristicType") = \(bind: type.rawValue) AND \(ident: "timestamp") < \(bind: date)
                """)
                .run()
        }
    }

    func entitiesWithRowCount(above limit: Int, since date: Date) async throws -> [EntityRowCount] {
        try await sqlDatabase().raw("""
            SELECT entityPlaceId, entityServiceName, entityCharacteristicType, COUNT(*) AS \(ident: "rowCount")
            FROM \(ident: EntityStorageDbItem.schema)
            WHERE \(ident: "timestamp") >= \(bind: date)
            GROUP BY entityPlaceId, entityServiceName, entityCharacteristicType
            HAVING COUNT(*) > \(bind: limit)
            """)
            .all()
            .map { row in
                try EntityRowCount(placeId: row.decode(column: "entityPlaceId", as: String.self),
                                   serviceName: row.decode(column: "entityServiceName", as: String.self),
                                   characteristicType: row.decode(column: "entityCharacteristicType", as: String.self),
                                   rows: row.decode(column: "rowCount", as: Int.self))
            }
    }
}

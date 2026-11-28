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

final class EntityStorageDbRepository: StorageRepository, Sendable {
    /// Resolved per query: a captured `app.db` is bound to one event loop and so to that loop's
    /// connection pool, which would funnel every query of this long-lived repository through it.
    let database: @Sendable () -> any Database
    private let log = Logger(label: "EntityStorageDbRepository")

    init(database: @escaping @Sendable () -> any Database) {
        self.database = database
    }

    func getCurrent(_ entityId: EntityId) async throws -> EntityStorageItem? {
        try await latestChanges(of: entityId, limit: 1).first
    }

    /// The newest change per entity, with the tiebreak of `getCurrent`. An entity of an unknown
    /// characteristic type is skipped.
    func getAllCurrent() async throws -> [EntityStorageItem] {
        try await newestChanges(ofType: nil)
    }

    /// Like `getAllCurrent`, for the entities of one characteristic type only.
    func getAllCurrent(of type: CharacteristicsType) async throws -> [EntityStorageItem] {
        try await newestChanges(ofType: type)
    }

    private func newestChanges(ofType type: CharacteristicsType?) async throws -> [EntityStorageItem] {
        let typeFilter: SQLQueryString = type.map { "WHERE e.\(ident: "characteristicType") = \(bind: $0.rawValue)" } ?? ""
        // One backward dive into `idx_entityChanges_entity_timestamp` per directory entry (the index carries the
        // primary key), instead of a window over the whole table.
        let rows = try await sqlDatabase().raw("""
            SELECT newest.\(ident: "id") AS \(ident: "id")
            FROM \(ident: EntityDbItem.schema) e,
            LATERAL (SELECT c.\(ident: "id") FROM \(ident: EntityChangeDbItem.schema) c
                     WHERE c.\(ident: "entityId") = e.\(ident: "id")
                     ORDER BY c.\(ident: "timestamp") DESC, c.\(ident: "id") DESC
                     LIMIT 1) AS newest
            \(typeFilter)
            """)
            .all()
        let ids = try rows.map { try $0.decode(column: "id", as: Int.self) }
        guard !ids.isEmpty else { return [] }
        var items: [EntityStorageItem] = []
        // Chunked, so a large directory does not build one huge IN list.
        for chunk in stride(from: 0, to: ids.count, by: 500).map({ Array(ids[$0..<min($0 + 500, ids.count)]) }) {
            let changes = try await EntityChangeDbItem.query(on: database())
                .filter(\.$id ~~ chunk)
                .with(\.$entity)
                .all()
            items += changes.compactMap { EntityStorageItem(entity: $0.entity, change: $0, withLastReport: true) }
        }
        return items
    }

    /// The newest `limit` changes of an entity, resolved through the directory entry. Equal timestamps are
    /// ordered by `id`, so `getCurrent` and `getAllCurrent` pick the same row.
    private func latestChanges(of entityId: EntityId, limit: Int) async throws -> [EntityStorageItem] {
        guard let entity = try await findEntity(entityId) else { return [] }
        let entityKey = try entity.requireID()
        return try await EntityChangeDbItem.query(on: database())
            .filter(\.$entity.$id == entityKey)
            .sort(\.$timestamp, .descending)
            .sort(\.$id, .descending)
            .limit(limit)
            .all()
            .compactMap { EntityStorageItem(entity: entity, change: $0, withLastReport: true) }
    }

    private func findEntity(_ entityId: EntityId) async throws -> EntityDbItem? {
        try await EntityDbItem.query(on: database())
            .filter(\.$placeId == entityId.placeId)
            .filter(\.$serviceName == entityId.name)
            .filter(\.$characteristicType == entityId.characteristicType.rawValue)
            .first()
    }

    /// The directory entry of an entity; created on first sight, and its name follows the newest one seen.
    private func entity(for entityId: EntityId) async throws -> EntityDbItem {
        if let existing = try await findEntity(entityId) {
            if let name = entityId.characteristicsName, existing.characteristicsName != name {
                existing.characteristicsName = name
                try await existing.save(on: database())
            }
            return existing
        }
        let created = EntityDbItem(placeId: entityId.placeId, serviceName: entityId.name,
                                   characteristicType: entityId.characteristicType.rawValue,
                                   characteristicsName: entityId.characteristicsName)
        do {
            try await created.save(on: database())
            return created
        } catch {
            // A concurrent write may have created it first (unique key).
            if let existing = try await findEntity(entityId) { return existing }
            throw error
        }
    }

    func add(_ item: EntityStorageItem) async throws {
        guard let value = item.value else {
            log.warning("Item without a value for its type is not stored", metadata: ["entityId": "\(item.entityId)"])
            return
        }
        let entity = try await entity(for: item.entityId)
        guard try await passesDeadBand(value, at: item.timestamp, of: entity) else { return }
        try await EntityChangeDbItem(entityId: entity.requireID(), timestamp: item.timestamp, value: value, shape: ValueDescriptor.descriptor(for: item.entityId.characteristicType).shape, origin: item.origin.rawValue)
            .save(on: database())
        if item.entityId.characteristicType.isHeatingRelated {
            log.debug("Stored heating entity item", metadata: ["entityId": "\(item.entityId)", "value": "\(value)"])
        }
    }

    /// One conditional UPDATE: the time only moves forward.
    func recordLastReport(of entityId: EntityId, at date: Date) async throws {
        try await EntityDbItem.query(on: database())
            .filter(\.$placeId == entityId.placeId)
            .filter(\.$serviceName == entityId.name)
            .filter(\.$characteristicType == entityId.characteristicType.rawValue)
            .group(.or) { group in
                group.filter(\.$lastReport == nil)
                group.filter(\.$lastReport < date)
            }
            .set(\.$lastReport, to: date)
            .update()
    }

    /// Whether the value moved out of its type's write dead band (the descriptor's storage rule) around the last
    /// stored change. Types without a dead band cost no extra query.
    private func passesDeadBand(_ value: Value, at timestamp: Date, of entity: EntityDbItem) async throws -> Bool {
        guard let type = CharacteristicsType(rawValue: entity.characteristicType),
              let deadBand = ValueDescriptor.descriptor(for: type).storage.deadBand,
              case .number(let number) = value else {
            return true
        }
        let entityKey = try entity.requireID()
        let last = try await EntityChangeDbItem.query(on: database())
            .filter(\.$entity.$id == entityKey)
            .sort(\.$timestamp, .descending)
            .sort(\.$id, .descending)
            .first()
        let lastStored = last.flatMap { row in row.number.map { (value: $0, timestamp: row.timestamp) } }
        return deadBand.shouldStore(number, at: timestamp, lastStored: lastStored)
    }

    /// The rollup rows of an entity, oldest hour first.
    func hourlyAggregates(of entityId: EntityId) async throws -> [EntityHourlyAggregate] {
        guard let entity = try await findEntity(entityId) else { return [] }
        let rows = try await sqlDatabase().raw("""
            SELECT * FROM \(ident: EntityHourlyAggregate.schema)
            WHERE \(ident: "entityId") = \(bind: entity.requireID())
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
        guard let entity = try await findEntity(entityId) else { return [] }
        let entityKey = try entity.requireID()
        var query = EntityChangeDbItem.query(on: database())
            .filter(\.$entity.$id == entityKey)
        if let startDate {
            query = query.filter(\.$timestamp >= startDate)
        }
        if let endDate {
            query = query.filter(\.$timestamp < endDate)
        }
        // Cursor-based pagination: fetch items older than the cursor.
        if let cursor {
            query = query.filter(\.$timestamp < cursor)
        }
        // The id breaks ties of equal timestamps (the index carries it, so no filesort). A page boundary on a tied
        // timestamp can still skip rows: the cursor is a timestamp only.
        return try await query
            .sort(\.$timestamp, .descending)
            .sort(\.$id, .descending)
            .limit(limit)
            .all()
            .compactMap { EntityStorageItem(entity: entity, change: $0) }
    }

    func getAllEntityIds() async throws -> [EntityId] {
        try await EntityDbItem.query(on: database()).all().compactMap { entity in
            guard let type = CharacteristicsType(rawValue: entity.characteristicType) else {
                log.warning("Entity of unknown characteristic type skipped", metadata: ["characteristicType": "\(entity.characteristicType)"])
                return nil
            }
            return EntityId(placeId: entity.placeId, name: entity.serviceName,
                            characteristicsName: entity.characteristicsName, characteristic: type)
        }
    }
}

extension EntityStorageDbRepository: EntityRetentionStore {
    static let deleteBatchSize = 10_000
    /// A rollup transaction covers at most this long a span of one entity.
    static let rollupSpan: TimeInterval = 86_400

    private func entityKeys(ofType type: CharacteristicsType) async throws -> [UUID] {
        try await EntityDbItem.query(on: database())
            .filter(\.$characteristicType == type.rawValue)
            .all()
            .map { try $0.requireID() }
    }

    /// Deletes per entity and in batches, each an exact range on `(entityId, timestamp)`, so a statement locks only
    /// its batch and a large backlog does not become one transaction.
    func deleteEntries(ofType type: CharacteristicsType, olderThan date: Date) async throws {
        let sql = try sqlDatabase()
        for entityKey in try await entityKeys(ofType: type) {
            try await sql.deleteInBatches(from: EntityChangeDbItem.schema,
                                          where: "\(ident: "entityId") = \(bind: entityKey) AND \(ident: "timestamp") < \(bind: date)",
                                          batchSize: Self.deleteBatchSize)
        }
    }

    /// Rolls the raw rows older than `date` up into hourly rows, one entity and at most a day per transaction, so a
    /// failed run resumes where it stopped and the first run over years of history is not one transaction.
    func rollUpHourly(type: CharacteristicsType, validRange: ClosedRange<Double>?, olderThan date: Date) async throws {
        let range = validRange ?? -Double.greatestFiniteMagnitude...Double.greatestFiniteMagnitude
        for entityKey in try await entityKeys(ofType: type) {
            while let oldest = try await EntityChangeDbItem.query(on: database())
                .filter(\.$entity.$id == entityKey)
                .filter(\.$timestamp < date)
                .sort(\.$timestamp, .ascending)
                .first()?.timestamp {
                try Task.checkCancellation()
                let from = Date(timeIntervalSince1970: (oldest.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
                let to = min(from.addingTimeInterval(Self.rollupSpan), date)
                try await database().transaction { database in
                    try await Self.rollUp(entityKey, from: from, to: to, range: range, on: database)
                }
            }
        }
    }

    private static func rollUp(_ entityKey: UUID, from: Date, to: Date, range: ClosedRange<Double>, on database: any Database) async throws {
        guard let sql = database as? SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL queries")
        }
        // An hour that already has a row (a late raw row) is merged; the update order matters
        // because MySQL assigns left to right, so the mean reads the old count. `maxValue` is a
        // reserved word, hence the backticks.
        try await sql.raw("""
            INSERT INTO \(ident: EntityHourlyAggregate.schema)
                (entityId, hourStart, `minValue`, `meanValue`, `maxValue`, `lastValue`, `valueCount`)
            SELECT * FROM (
                SELECT entityId, hourStart,
                       MIN(v) AS minV, AVG(v) AS meanV, MAX(v) AS maxV, MAX(CASE WHEN rn = 1 THEN v END) AS lastV, COUNT(*) AS countV
                FROM (
                    SELECT c.\(ident: "entityId") AS entityId,
                           TIMESTAMP(DATE_FORMAT(c.\(ident: "timestamp"), '%Y-%m-%d %H:00:00')) AS hourStart,
                           c.\(ident: "number") AS v,
                           ROW_NUMBER() OVER (PARTITION BY DATE_FORMAT(c.\(ident: "timestamp"), '%Y-%m-%d %H')
                                              ORDER BY c.\(ident: "timestamp") DESC, c.\(ident: "id") DESC) AS rn
                    FROM \(ident: EntityChangeDbItem.schema) c
                    WHERE c.\(ident: "entityId") = \(bind: entityKey)
                      AND c.\(ident: "timestamp") >= \(bind: from) AND c.\(ident: "timestamp") < \(bind: to)
                      AND c.\(ident: "number") BETWEEN \(bind: range.lowerBound) AND \(bind: range.upperBound)
                ) raw
                GROUP BY entityId, hourStart
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
            DELETE FROM \(ident: EntityChangeDbItem.schema)
            WHERE \(ident: "entityId") = \(bind: entityKey)
              AND \(ident: "timestamp") >= \(bind: from) AND \(ident: "timestamp") < \(bind: to)
            """)
            .run()
    }

    func entitiesWithRowCount(above limit: Int, since date: Date) async throws -> [EntityRowCount] {
        try await sqlDatabase().raw("""
            SELECT e.\(ident: "placeId") AS entityPlaceId, e.\(ident: "serviceName") AS entityServiceName,
                   e.\(ident: "characteristicType") AS entityCharacteristicType, COUNT(*) AS \(ident: "rowCount")
            FROM \(ident: EntityChangeDbItem.schema) c
            JOIN \(ident: EntityDbItem.schema) e ON e.\(ident: "id") = c.\(ident: "entityId")
            WHERE c.\(ident: "timestamp") >= \(bind: date)
            GROUP BY e.\(ident: "id"), e.\(ident: "placeId"), e.\(ident: "serviceName"), e.\(ident: "characteristicType")
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

//
//  06_AddLookupIndexes.swift
//  HomeAutomationServer
//

import Fluent
import SQLKit
import Vapor

/// Indexes for the queries that run on every event and in the daily cleanup. Without them each
/// lookup of an entity's current value is a full table scan plus a filesort; with them it reads the
/// newest index entries of that entity backwards.
///
/// Idempotent: MySQL has no `CREATE INDEX IF NOT EXISTS` and each index is its own statement, so a
/// run that dies after the first index would otherwise fail on every later boot with "Duplicate key
/// name". Existing indexes are skipped, missing ones dropped from `revert`.
struct AddLookupIndexes: AsyncMigration {
    // Key length of the composite index: 3 × VARCHAR(255) utf8mb4 (3 × 1020 bytes) + DATETIME(6)
    // (8 bytes) ≈ 3068 of InnoDB's 3072 bytes (DYNAMIC row format, the default since MySQL 5.7).
    // Adding `entityCharacteristicsName` would exceed it ("Specified key was too long").
    private static let indexes: [(name: String, table: String, columns: [String])] = [
        ("idx_entityItems_entity_timestamp", EntityStorageDbItem.schema, ["entityPlaceId", "entityServiceName", "entityCharacteristicType", "timestamp"]),
        ("idx_entityItems_timestamp", EntityStorageDbItem.schema, ["timestamp"]),
        ("idx_automationRuns_name_startedAt", AutomationRunDbItem.schema, ["automationName", "startedAt"]),
        ("idx_automationRuns_startedAt", AutomationRunDbItem.schema, ["startedAt"])
    ]

    func prepare(on database: Database) async throws {
        let sql = try Self.sqlDatabase(database)
        for index in Self.indexes where try await !Self.indexExists(index.name, on: index.table, in: sql) {
            let builder = sql.create(index: index.name).on(index.table)
            for column in index.columns {
                builder.column(column)
            }
            try await builder.run()
        }
    }

    func revert(on database: Database) async throws {
        let sql = try Self.sqlDatabase(database)
        for index in Self.indexes where try await Self.indexExists(index.name, on: index.table, in: sql) {
            try await sql.drop(index: index.name)
                .on(index.table)
                .run()
        }
    }

    private static func indexExists(_ name: String, on table: String, in sql: any SQLDatabase) async throws -> Bool {
        let row = try await sql.raw("""
            SELECT COUNT(*) AS \(ident: "count")
            FROM information_schema.statistics
            WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = \(bind: table) AND INDEX_NAME = \(bind: name)
            """)
            .first()
        return try (row?.decode(column: "count", as: Int.self) ?? 0) > 0
    }

    private static func sqlDatabase(_ database: Database) throws -> any SQLDatabase {
        guard let sql = database as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL queries")
        }
        return sql
    }
}

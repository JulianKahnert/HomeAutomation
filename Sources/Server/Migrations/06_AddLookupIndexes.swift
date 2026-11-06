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
struct AddLookupIndexes: AsyncMigration {
    private static let indexes: [(name: String, table: String, columns: [String])] = [
        ("idx_entityItems_entity_timestamp", EntityStorageDbItem.schema, ["entityPlaceId", "entityServiceName", "entityCharacteristicType", "timestamp"]),
        ("idx_entityItems_timestamp", EntityStorageDbItem.schema, ["timestamp"]),
        ("idx_automationRuns_name_startedAt", AutomationRunDbItem.schema, ["automationName", "startedAt"]),
        ("idx_automationRuns_startedAt", AutomationRunDbItem.schema, ["startedAt"])
    ]

    func prepare(on database: Database) async throws {
        let sql = try Self.sqlDatabase(database)
        for index in Self.indexes {
            let builder = sql.create(index: index.name).on(index.table)
            for column in index.columns {
                builder.column(column)
            }
            try await builder.run()
        }
    }

    func revert(on database: Database) async throws {
        let sql = try Self.sqlDatabase(database)
        for index in Self.indexes {
            try await sql.drop(index: index.name)
                .on(index.table)
                .run()
        }
    }

    private static func sqlDatabase(_ database: Database) throws -> any SQLDatabase {
        guard let sql = database as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL queries")
        }
        return sql
    }
}

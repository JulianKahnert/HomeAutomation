//
//  15_CreateNarrowStorage.swift
//  HomeAutomationServer
//

import Fluent
import SQLKit
import Vapor

/// The narrow storage: a directory of entities and one row per change with a number and a text column.
/// Existing `entityItems` rows are not moved; the old table stays but is no longer written.
struct CreateNarrowStorage: AsyncMigration {
    static let changeIndex = "idx_entityChanges_entity_timestamp"
    static let timestampIndex = "idx_entityChanges_timestamp"

    func prepare(on database: Database) async throws {
        // The unique key is 3 × VARCHAR(255) utf8mb4 = 3060 bytes, inside InnoDB's 3072 (see migration 06).
        try await database.schema(EntityDbItem.schema)
            .id()
            .field("placeId", .string, .required)
            .field("serviceName", .string, .required)
            .field("characteristicType", .string, .required)
            .field("characteristicsName", .string)
            .unique(on: "placeId", "serviceName", "characteristicType")
            .create()

        try await database.schema(EntityChangeDbItem.schema)
            .id()
            .field("entityId", .uuid, .required, .references(EntityDbItem.schema, "id", onDelete: .cascade))
            .field("timestamp", .datetime, .required)
            .field("number", .double)
            .field("text", .string)
            .field("origin", .string, .required, .sql(.default("homekit")))
            .create()

        let sql = try Self.sqlDatabase(database)
        try await sql.create(index: Self.changeIndex).on(EntityChangeDbItem.schema)
            .column("entityId").column("timestamp").run()
        try await sql.create(index: Self.timestampIndex).on(EntityChangeDbItem.schema)
            .column("timestamp").run()
    }

    func revert(on database: Database) async throws {
        try await database.schema(EntityChangeDbItem.schema).delete()
        try await database.schema(EntityDbItem.schema).delete()
    }

    private static func sqlDatabase(_ database: Database) throws -> any SQLDatabase {
        guard let sql = database as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL queries")
        }
        return sql
    }
}

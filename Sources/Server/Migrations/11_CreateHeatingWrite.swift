//
//  11_CreateHeatingWrite.swift
//  HomeAutomationServer
//

import Fluent
import SQLKit
import Vapor

/// Dropped again by `MoveHeatingWritesToJournal`. The persisted record of the server's writes to radiators: reason, written value and plan target.
/// A few rows per room and day, kept for good: the index serves the lookup of a radiator's last write on
/// every contact change and the range queries of the room detail (key ≈ 2 × 1020 + 8 bytes, within InnoDB's 3072).
struct CreateHeatingWrite: AsyncMigration {
    static let table = "heatingWrites"
    static let indexName = "idx_heatingWrites_place_name_timestamp"

    func prepare(on database: Database) async throws {
        try await database.schema(Self.table)
            .id()
            .field("timestamp", .datetime, .required)
            .field("placeId", .string, .required)
            .field("name", .string, .required)
            .field("characteristicsName", .string)
            .field("characteristicType", .string, .required)
            .field("reason", .string, .required)
            .field("actionName", .string, .required)
            .field("isActive", .bool)
            .field("targetTemperatureInC", .double)
            .field("planTargetInC", .double)
            .field("sentToDevice", .bool, .required)
            .create()
        guard let sql = database as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL queries")
        }
        try await sql.create(index: Self.indexName)
            .on(Self.table)
            .column("placeId")
            .column("name")
            .column("timestamp")
            .run()
    }

    func revert(on database: Database) async throws {
        try await database.schema(Self.table).delete()
    }
}

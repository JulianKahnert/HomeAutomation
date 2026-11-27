//
//  09_CreateEntityHourlyAggregate.swift
//  HomeAutomationServer
//

import Fluent
import SQLKit
import Vapor

/// Hourly rollup of the types whose `StoragePolicy` condenses them (lux, CO₂), plus the index the
/// per-type cleanup and rollup read `entityItems` through.
struct CreateEntityHourlyAggregate: AsyncMigration {
    static let typeTimestampIndex = "idx_entityItems_type_timestamp"

    func prepare(on database: Database) async throws {
        // The natural key is the primary key: one row per entity and hour, read per entity by time.
        // 3 × VARCHAR(255) utf8mb4 + DATETIME fits InnoDB's 3072-byte key limit (see migration 06).
        try await database.schema(EntityHourlyAggregate.schema)
            .field("entityPlaceId", .string, .required)
            .field("entityServiceName", .string, .required)
            .field("entityCharacteristicType", .string, .required)
            .field("hourStart", .datetime, .required)
            .field("minValue", .double, .required)
            .field("meanValue", .double, .required)
            .field("maxValue", .double, .required)
            .field("lastValue", .double, .required)
            .field("valueCount", .int, .required)
            .compositeIdentifier(over: "entityPlaceId", "entityServiceName", "entityCharacteristicType", "hourStart")
            .create()

        // Without it, selecting one type's old rows walks every old row of all types kept forever.
        try await Self.sqlDatabase(database).create(index: Self.typeTimestampIndex)
            .on(LegacyEntityItems.schema)
            .column("entityCharacteristicType")
            .column("timestamp")
            .run()
    }

    func revert(on database: Database) async throws {
        try await Self.sqlDatabase(database).drop(index: Self.typeTimestampIndex)
            .on(LegacyEntityItems.schema)
            .run()
        try await database.schema(EntityHourlyAggregate.schema).delete()
    }

    private static func sqlDatabase(_ database: Database) throws -> any SQLDatabase {
        guard let sql = database as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL queries")
        }
        return sql
    }
}

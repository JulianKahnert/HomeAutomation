//
//  11_CreateHeatingWrite.swift
//  HomeAutomationServer
//

import Fluent

/// The persisted record of the server's writes to radiators: reason, written value and plan target.
/// A few rows per room and day, so no index beyond the primary key.
struct CreateHeatingWrite: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(HeatingWriteDbItem.schema)
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
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(HeatingWriteDbItem.schema).delete()
    }
}

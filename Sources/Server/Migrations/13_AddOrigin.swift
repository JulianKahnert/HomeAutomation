//
//  13_AddOrigin.swift
//  HomeAutomationServer
//

import Fluent

/// Adds the origin of a change to the entityItems table. Every row so far came from HomeKit.
struct AddOrigin: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(LegacyEntityItems.schema)
            .field("origin", .string, .required, .sql(.default("homekit")))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(LegacyEntityItems.schema)
            .deleteField("origin")
            .update()
    }
}

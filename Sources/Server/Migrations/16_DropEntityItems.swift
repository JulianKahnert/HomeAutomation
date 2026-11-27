//
//  16_DropEntityItems.swift
//  HomeAutomationServer
//

import Fluent

/// Removes the old wide `entityItems` table. Since `CreateNarrowStorage` nothing wrote or read it; its rows
/// were never moved, so this drops that history. The migration cannot be undone: a revert leaves the table gone.
struct DropEntityItems: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(LegacyEntityItems.schema).delete()
    }

    func revert(on database: Database) async throws {}
}

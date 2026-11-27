//
//  16_MoveHeatingWritesToJournal.swift
//  HomeAutomationServer
//

import Fluent

/// The radiator commands live in the journal (their reason and plan target already did), so the journal gets the
/// value a command wrote and the heating-write table goes. The old rows are not moved: the plan history before this
/// migration shows the plan as configured, the events of those days are gone.
struct MoveHeatingWritesToJournal: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(JournalDbItem.schema)
            .field("commandValue", .double)
            .update()
        try await database.schema(CreateHeatingWrite.table).delete()
    }

    func revert(on database: Database) async throws {
        try await database.schema(JournalDbItem.schema)
            .deleteField("commandValue")
            .update()
        try await CreateHeatingWrite().prepare(on: database)
    }
}

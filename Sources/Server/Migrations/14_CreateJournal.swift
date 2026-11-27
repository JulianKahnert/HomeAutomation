//
//  14_CreateJournal.swift
//  HomeAutomationServer
//

import Fluent
import SQLKit

/// One journal table for runs, commands and pushes (see `JournalDbItem`). The rows of the run table
/// move over and the run table goes.
struct CreateJournal: AsyncMigration {
    private static let indexes: [(name: String, columns: [String])] = [
        ("idx_journal_kind_timestamp", ["kind", "timestamp"]),
        ("idx_journal_runId", ["runId"]),
        ("idx_journal_title_timestamp", ["title", "timestamp"])
    ]

    func prepare(on database: Database) async throws {
        try await database.schema(JournalDbItem.schema)
            .id()
            .field("kind", .string, .required)
            .field("timestamp", .datetime, .required)
            .field("runId", .uuid)
            .field("title", .string, .required)
            .field("detail", .custom("VARCHAR(1000)"), .required)
            .field("entityPlaceId", .string)
            .field("entityName", .string)
            .field("entityCharacteristicsName", .string)
            .field("entityCharacteristicType", .string)
            .field("triggerKind", .string)
            .field("outcome", .string)
            .field("endedAt", .datetime)
            .field("errorDescription", .custom("TEXT"))
            .field("status", .string)
            .field("hasCacheHit", .bool)
            .field("reason", .string)
            .field("planTargetInC", .double)
            .field("pushId", .string)
            .create()

        guard let sql = database as? any SQLDatabase else { return }
        for index in Self.indexes {
            let builder = sql.create(index: index.name).on(JournalDbItem.schema)
            for column in index.columns {
                builder.column(column)
            }
            try await builder.run()
        }
        try await sql.raw("""
            INSERT INTO \(ident: JournalDbItem.schema)
                (id, kind, timestamp, runId, title, detail, entityPlaceId, entityName, entityCharacteristicsName,
                 entityCharacteristicType, triggerKind, outcome, endedAt, errorDescription)
            SELECT id, 'run', startedAt, id, automationName, triggerSummary, triggerPlaceId, triggerName,
                   triggerCharacteristicsName, triggerCharacteristicType, triggerKind, outcome, endedAt, errorDescription
            FROM \(ident: "automationRuns")
            """).run()
        try await database.schema("automationRuns").delete()
    }

    func revert(on database: Database) async throws {
        try await database.schema(JournalDbItem.schema).delete()
        try await CreateAutomationRun().prepare(on: database)
    }
}

//
//  05_CreateAutomationRun.swift
//  HomeAutomationServer
//

import Fluent

struct CreateAutomationRun: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(AutomationRunDbItem.schema)
            .id()
            .field("automationName", .string, .required)
            .field("startedAt", .datetime, .required)
            .field("endedAt", .datetime)
            .field("triggerKind", .string, .required)
            .field("triggerPlaceId", .string)
            .field("triggerName", .string)
            .field("triggerCharacteristicsName", .string)
            .field("triggerCharacteristicType", .string)
            .field("triggerSummary", .custom("VARCHAR(1000)"), .required)
            .field("outcome", .string, .required)
            .field("errorDescription", .custom("TEXT"))
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(AutomationRunDbItem.schema).delete()
    }
}

//
//  12_AddHeatingWriteSentToDevice.swift
//  HomeAutomationServer
//

import Fluent

/// Marks the heating writes that only record a plan target while the room was off. Existing rows were all sent.
struct AddHeatingWriteSentToDevice: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(HeatingWriteDbItem.schema)
            .field("sentToDevice", .bool, .required, .sql(.default(true)))
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema(HeatingWriteDbItem.schema)
            .deleteField("sentToDevice")
            .update()
    }
}

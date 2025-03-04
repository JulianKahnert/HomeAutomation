//
//  CreateEntityStorageDbItem.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 06.02.25.
//

import Fluent

struct PushDeviceDbItem: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(PushDevice.schema)
            .id()
            .field("deviceToken", .string)
            .field("createdAt", .datetime)
            .field("updatedAt", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(PushDevice.schema).delete()
    }
}

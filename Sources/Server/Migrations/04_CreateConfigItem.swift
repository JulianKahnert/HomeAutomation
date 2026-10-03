//
//  04_CreateConfigItem.swift
//  HomeAutomationServer
//

import Fluent

struct CreateConfigItem: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(ConfigItem.schema)
            .id()
            // `.data` maps to MySQL BLOB, capped at 64 KB; configs may be larger.
            .field("json", .custom("LONGBLOB"), .required)
            .field("updatedAt", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(ConfigItem.schema).delete()
    }
}

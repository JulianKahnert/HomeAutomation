//
//  02_DeviceTokenItem.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 06.02.25.
//

import Fluent

struct DeviceTokenItem: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(DeviceToken.schema)
            .id()
            .field("deviceName", .string, .required)
            .field("tokenString", .custom("VARCHAR(500)"), .required)
            .field("tokenType", .string, .required)
            .field("activityType", .string)
            .field("createdAt", .datetime)
            .field("updatedAt", .datetime)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(DeviceToken.schema).delete()
    }
}

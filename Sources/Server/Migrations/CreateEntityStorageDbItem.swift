//
//  CreateEntityStorageDbItem.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 06.02.25.
//

import Fluent

struct CreateEntityStorageDbItem: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema(EntityStorageDbItem.schema)
            .id()
            .field("timestamp", .datetime, .required)
            .field("entityPlaceId", .string, .required)
            .field("entityServiceName", .string, .required)
            .field("entityCharacteristicsName", .string)
            .field("entityCharacteristicType", .string, .required)
            .field("motionDetected", .bool)
            .field("illuminanceInLux", .double)
            .field("isDeviceOn", .bool)
            .field("isContactOpen", .bool)
            .field("isDoorLocked", .bool)
            .field("stateOfCharge", .int)
            .field("isHeaterActive", .bool)
            .create()
    }

    func revert(on database: Database) async throws {
        try await database.schema(EntityStorageDbItem.schema).delete()
    }
}

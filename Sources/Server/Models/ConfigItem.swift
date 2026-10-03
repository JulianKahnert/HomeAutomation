//
//  ConfigItem.swift
//  HomeAutomationServer
//

import Fluent
import Foundation

/// The server config (`ConfigDTO`) as one JSON blob — the table holds a single row.
final class ConfigItem: Model, @unchecked Sendable {
    static let schema = "config"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "json")
    var json: Data

    @Timestamp(key: "updatedAt", on: .update)
    var updatedAt: Date?

    init() { }

    static func loadJSON(on database: any Database) async throws -> Data? {
        try await query(on: database).first()?.json
    }

    static func save(json: Data, on database: any Database) async throws {
        let item = try await query(on: database).first() ?? ConfigItem()
        item.json = json
        try await item.save(on: database)
    }
}

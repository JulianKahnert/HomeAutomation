//
//  01_InitialSchema.swift
//  HomeAutomationServer
//

import Fluent
import SQLKit
import Vapor

/// The migrations of the server, in order. A new database starts from the one initial schema;
/// the data of an old database is moved over by a separate script, never by a migration.
enum ServerMigrations {
    static var all: [any Migration] { [InitialSchema()] }
}

/// Creates every table the server uses. The final schema is documented in `docs/database-schema.md`.
///
/// Key lengths: an index key may be 3072 bytes in InnoDB (DYNAMIC row format); a utf8mb4 character counts 4 bytes.
/// The code columns (`kind`, `status`, `origin`, …) are short on purpose, so the journal indexes stay far below it.
/// The narrow integer types are spelled out because Fluent maps `.int8`/`.uint8` to INT on MySQL.
/// Every table with text columns gets the binary collation `utf8mb4_0900_bin`: names compare exactly as Swift does.
struct InitialSchema: AsyncMigration {
    /// The tables with text columns; they are converted to a binary collation.
    private static let textTables = [
        DeviceToken.schema, WeatherHour.schema, EntityDbItem.schema, EntityChangeDbItem.schema, JournalDbItem.schema,
        HomekitInventoryDbItem.schema
    ]
    private static let tables = [
        DeviceToken.schema, ConfigItem.schema, WeatherHour.schema, EntityHourlyAggregate.schema,
        EntityChangeDbItem.schema, EntityDbItem.schema, JournalDbItem.schema, HomekitInventoryDbItem.schema
    ]

    func prepare(on database: Database) async throws {
        guard let sql = database as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL queries")
        }

        try await database.schema(DeviceToken.schema)
            .id()
            .field("deviceName", .string, .required)
            .field("tokenString", .custom("VARCHAR(500)"), .required)
            .field("tokenType", .custom("VARCHAR(32)"), .required)
            .field("activityType", .string)
            .field("createdAt", .datetime)
            .field("updatedAt", .datetime)
            .create()

        try await database.schema(ConfigItem.schema)
            .id()
            // `.data` maps to MySQL BLOB, capped at 64 KB; configs may be larger.
            .field("json", .custom("LONGBLOB"), .required)
            .field("updatedAt", .datetime)
            .create()

        try await database.schema(WeatherHour.schema)
            .field("locationKey", .custom("VARCHAR(64)"), .required)
            .field("hour", .datetime, .required)
            .field("fetchedAt", .datetime, .required)
            .field("temperature2mC", .double)
            .field("apparentTemperatureC", .double)
            .field("relativeHumidity2mPercent", .custom("TINYINT UNSIGNED"))
            .field("dewPoint2mC", .double)
            .field("precipitationMm", .double)
            .field("cloudCoverPercent", .custom("TINYINT UNSIGNED"))
            .field("windSpeed10mKmh", .double)
            .field("windDirection10mDeg", .custom("SMALLINT UNSIGNED"))
            .field("shortwaveRadiationWm2", .double)
            .field("directRadiationWm2", .double)
            .field("diffuseRadiationWm2", .double)
            .field("directNormalIrradianceWm2", .double)
            .field("sunshineDurationS", .double)
            .field("isDay", .bool)
            .compositeIdentifier(over: "locationKey", "hour")
            .create()

        try await database.schema(EntityDbItem.schema)
            .id()
            .field("placeId", .string, .required)
            .field("serviceName", .string, .required)
            .field("characteristicType", .string, .required)
            .field("characteristicsName", .string)
            .field("lastReport", .datetime)
            .unique(on: "placeId", "serviceName", "characteristicType")
            .create()

        try await database.schema(EntityHourlyAggregate.schema)
            .field("entityId", .uuid, .required, .references(EntityDbItem.schema, "id", onDelete: .restrict))
            .field("hourStart", .datetime, .required)
            .field("minValue", .double, .required)
            .field("meanValue", .double, .required)
            .field("maxValue", .double, .required)
            .field("lastValue", .double, .required)
            .field("valueCount", .int, .required)
            .compositeIdentifier(over: "entityId", "hourStart")
            .create()

        // An auto-increment BIGINT key appends new rows at the end of the clustered index; a random UUID would
        // insert into the middle of the biggest table. The foreign key is added below, after the index it uses.
        try await database.schema(EntityChangeDbItem.schema)
            .field(.id, .int64, .identifier(auto: true))
            .field("entityId", .uuid, .required)
            .field("timestamp", .datetime, .required)
            .field("number", .double)
            .field("text", .string)
            .field("origin", .custom("VARCHAR(32)"), .required, .sql(.default("homekit")))
            .create()

        try await database.schema(JournalDbItem.schema)
            .id()
            .field("kind", .custom("VARCHAR(16)"), .required)
            .field("timestamp", .datetime, .required)
            .field("runId", .uuid)
            .field("title", .string, .required)
            .field("detail", .custom("VARCHAR(1000)"), .required)
            .field("entityPlaceId", .string)
            .field("entityName", .string)
            .field("entityCharacteristicsName", .string)
            .field("entityCharacteristicType", .string)
            .field("triggerKind", .custom("VARCHAR(32)"))
            .field("outcome", .custom("VARCHAR(32)"))
            .field("endedAt", .datetime)
            .field("errorDescription", .custom("TEXT"))
            .field("status", .custom("VARCHAR(32)"))
            .field("reason", .custom("VARCHAR(32)"))
            .field("pushId", .string)
            .field("commandValue", .double)
            .create()

        // The inventory is replaced as a whole with each snapshot of the adapter, so it has no unique key.
        try await database.schema(HomekitInventoryDbItem.schema)
            .field(.id, .int64, .identifier(auto: true))
            .field("homeName", .string, .required)
            .field("roomName", .string, .required)
            .field("accessoryName", .string, .required)
            .field("manufacturer", .string)
            .field("model", .string)
            .field("serviceType", .custom("VARCHAR(64)"), .required)
            .field("serviceName", .string, .required)
            .field("characteristicType", .custom("VARCHAR(64)"), .required)
            .field("characteristicDescription", .string, .required)
            .field("mappedType", .custom("VARCHAR(32)"))
            .field("isReadable", .bool, .required)
            .field("isNotifiable", .bool, .required)
            .field("isWritable", .bool, .required)
            .field("value", .string)
            .field("syncedAt", .datetime, .required)
            .create()

        for table in Self.textTables {
            try await sql.raw("ALTER TABLE \(ident: table) CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_bin").run()
        }

        let indexes: [(name: String, table: String, columns: [String])] = [
            ("idx_entityChanges_entity_timestamp", EntityChangeDbItem.schema, ["entityId", "timestamp"]),
            // Covers the daily count of rows per entity without reading the table.
            ("idx_entityChanges_timestamp_entity", EntityChangeDbItem.schema, ["timestamp", "entityId"]),
            ("idx_journal_kind_timestamp", JournalDbItem.schema, ["kind", "timestamp"]),
            ("idx_journal_runId", JournalDbItem.schema, ["runId"]),
            ("idx_journal_kind_title_timestamp", JournalDbItem.schema, ["kind", "title", "timestamp"]),
            ("idx_journal_kind_place_timestamp", JournalDbItem.schema, ["kind", "entityPlaceId", "timestamp"]),
            // "Which characteristics of a mapped type does HomeKit have", and everything of a room.
            ("idx_homekitInventory_mappedType_room_accessory", HomekitInventoryDbItem.schema, ["mappedType", "roomName", "accessoryName"]),
            ("idx_homekitInventory_room_accessory", HomekitInventoryDbItem.schema, ["roomName", "accessoryName"])
        ]
        for index in indexes {
            let builder = sql.create(index: index.name).on(index.table)
            for column in index.columns {
                builder.column(column)
            }
            try await builder.run()
        }

        // The foreign key uses `idx_entityChanges_entity_timestamp`, so MySQL creates no extra index for it. RESTRICT:
        // the app never deletes an entity, and a manual delete must not cascade over years of rows in one statement.
        try await sql.raw("""
            ALTER TABLE \(ident: EntityChangeDbItem.schema)
            ADD CONSTRAINT \(ident: "fk_entityChanges_entityId") FOREIGN KEY (\(ident: "entityId"))
            REFERENCES \(ident: EntityDbItem.schema) (\(ident: "id")) ON DELETE RESTRICT
            """).run()
        // A row with neither a number nor a text is meaningless (MySQL 8.0.16+ enforces CHECK).
        try await sql.raw("""
            ALTER TABLE \(ident: EntityChangeDbItem.schema)
            ADD CONSTRAINT \(ident: "chk_entityChanges_value") CHECK (\(ident: "number") IS NOT NULL OR \(ident: "text") IS NOT NULL)
            """).run()
    }

    func revert(on database: Database) async throws {
        for table in Self.tables {
            try await database.schema(table).delete()
        }
    }
}

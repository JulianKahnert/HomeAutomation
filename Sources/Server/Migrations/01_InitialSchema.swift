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

/// Creates every table the server uses. The final schema is documented in `notes/T26.md`.
///
/// Key lengths: a key over 3 × VARCHAR(255) utf8mb4 (3060 bytes) plus a DATETIME(6) (8 bytes) fits
/// InnoDB's 3072 bytes (DYNAMIC row format); a fourth string column would not.
/// The narrow integer types are spelled out because Fluent maps `.int8`/`.uint8` to INT on MySQL.
struct InitialSchema: AsyncMigration {
    private static let tables = [
        DeviceToken.schema, ConfigItem.schema, WeatherHour.schema, EntityHourlyAggregate.schema,
        EntityChangeDbItem.schema, EntityDbItem.schema, JournalDbItem.schema
    ]

    func prepare(on database: Database) async throws {
        guard let sql = database as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL queries")
        }

        try await database.schema(DeviceToken.schema)
            .id()
            .field("deviceName", .string, .required)
            .field("tokenString", .custom("VARCHAR(500)"), .required)
            .field("tokenType", .string, .required)
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
            .field("temperature2mC", .float)
            .field("apparentTemperatureC", .float)
            .field("relativeHumidity2mPercent", .custom("TINYINT UNSIGNED"))
            .field("dewPoint2mC", .float)
            .field("precipitationMm", .float)
            .field("cloudCoverPercent", .custom("TINYINT UNSIGNED"))
            .field("windSpeed10mKmh", .float)
            .field("windDirection10mDeg", .custom("SMALLINT UNSIGNED"))
            .field("shortwaveRadiationWm2", .float)
            .field("directRadiationWm2", .float)
            .field("diffuseRadiationWm2", .float)
            .field("directNormalIrradianceWm2", .float)
            .field("sunshineDurationS", .float)
            .field("isDay", .bool)
            .compositeIdentifier(over: "locationKey", "hour")
            .create()

        try await database.schema(EntityHourlyAggregate.schema)
            .field("entityPlaceId", .string, .required)
            .field("entityServiceName", .string, .required)
            .field("entityCharacteristicType", .string, .required)
            .field("hourStart", .datetime, .required)
            .field("minValue", .double, .required)
            .field("meanValue", .double, .required)
            .field("maxValue", .double, .required)
            .field("lastValue", .double, .required)
            .field("valueCount", .int, .required)
            .compositeIdentifier(over: "entityPlaceId", "entityServiceName", "entityCharacteristicType", "hourStart")
            .create()

        try await database.schema(EntityDbItem.schema)
            .id()
            .field("placeId", .string, .required)
            .field("serviceName", .string, .required)
            .field("characteristicType", .string, .required)
            .field("characteristicsName", .string)
            .unique(on: "placeId", "serviceName", "characteristicType")
            .create()

        try await database.schema(EntityChangeDbItem.schema)
            .id()
            .field("entityId", .uuid, .required, .references(EntityDbItem.schema, "id", onDelete: .cascade))
            .field("timestamp", .datetime, .required)
            .field("number", .double)
            .field("text", .string)
            .field("origin", .string, .required, .sql(.default("homekit")))
            .create()

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
            .field("commandValue", .double)
            .create()

        let indexes: [(name: String, table: String, columns: [String])] = [
            ("idx_entityChanges_entity_timestamp", EntityChangeDbItem.schema, ["entityId", "timestamp"]),
            ("idx_entityChanges_timestamp", EntityChangeDbItem.schema, ["timestamp"]),
            ("idx_journal_kind_timestamp", JournalDbItem.schema, ["kind", "timestamp"]),
            ("idx_journal_runId", JournalDbItem.schema, ["runId"]),
            ("idx_journal_title_timestamp", JournalDbItem.schema, ["title", "timestamp"])
        ]
        for index in indexes {
            let builder = sql.create(index: index.name).on(index.table)
            for column in index.columns {
                builder.column(column)
            }
            try await builder.run()
        }
    }

    func revert(on database: Database) async throws {
        for table in Self.tables {
            try await database.schema(table).delete()
        }
    }
}

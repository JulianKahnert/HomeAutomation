# Database schema

The server's MySQL schema is created by one migration, `InitialSchema` in `Sources/Server/Migrations/01_InitialSchema.swift`
(`ServerMigrations.all` is the list; `configure.swift` and the MySQL tests register it). A new database starts from it. The data of
an old database is moved over by a separate script, never by a migration.

MySQL types: `id` is a UUID primary key (VARBINARY(16)) on every table that has one, except `entityChanges`, whose `id` is a BIGINT AUTO_INCREMENT; `string` is VARCHAR(255); `datetime` is DATETIME(6); `double` is DOUBLE; `bool` is BOOL.

Every table with text columns is converted to the binary collation `utf8mb4_0900_bin` right after it is created, so strings compare exactly as in Swift: `Bad` and `bad`, or `Küche` and `Kuche`, are different names.

## Tables

- `deviceToken`: id; deviceName string NOT NULL; tokenString VARCHAR(500) NOT NULL; tokenType VARCHAR(32) NOT NULL; activityType string; createdAt datetime; updatedAt datetime.
- `config`: id; json LONGBLOB NOT NULL; updatedAt datetime.
- `weatherHours`: primary key (locationKey, hour); locationKey VARCHAR(64) NOT NULL; hour datetime NOT NULL; fetchedAt datetime NOT NULL; temperature2mC, apparentTemperatureC, dewPoint2mC, precipitationMm, windSpeed10mKmh, shortwaveRadiationWm2, directRadiationWm2, diffuseRadiationWm2, directNormalIrradianceWm2, sunshineDurationS DOUBLE; relativeHumidity2mPercent, cloudCoverPercent TINYINT UNSIGNED; windDirection10mDeg SMALLINT UNSIGNED; isDay bool.
- `entityHourlyAggregates`: primary key (entityId, hourStart); entityId UUID NOT NULL, foreign key to `entities.id` (ON DELETE RESTRICT); hourStart datetime NOT NULL; minValue, meanValue, maxValue, lastValue DOUBLE NOT NULL; valueCount INT NOT NULL.
- `entities` (`EntityDbItem`): id; placeId, serviceName, characteristicType string NOT NULL; characteristicsName string; lastReport datetime (nullable: when the entity last reported, an unchanged report included; written at most every five minutes per entity, for a change like for an unchanged report, so it lags by up to five minutes; the readers return the later of it and the newest change's timestamp, so a stored change shows as a report at once; `NULL` until the entity reports after the column exists); UNIQUE (placeId, serviceName, characteristicType).
- `entityChanges` (`EntityChangeDbItem`): id BIGINT AUTO_INCREMENT (rows append at the end of the clustered index; equal timestamps order by write, the higher id is the later one); entityId UUID NOT NULL, foreign key `fk_entityChanges_entityId` to `entities.id` ON DELETE RESTRICT (the app never deletes an entity; to remove one by hand, delete its changes in batches first); timestamp datetime NOT NULL; number DOUBLE; text string; origin VARCHAR(32) NOT NULL DEFAULT 'homekit'. CHECK `chk_entityChanges_value`: `number IS NOT NULL OR text IS NOT NULL`. Indexes `idx_entityChanges_entity_timestamp` (entityId, timestamp; serves every per-entity read, and the foreign key) and `idx_entityChanges_timestamp_entity` (timestamp, entityId; covers the daily row count per entity). Nothing else: the foreign key creates no index of its own because its index exists first.
- `journal` (`JournalDbItem`): id; kind VARCHAR(16) NOT NULL (`run`, `command`, `push`); timestamp datetime NOT NULL; runId UUID; title string NOT NULL; detail VARCHAR(1000) NOT NULL; entityPlaceId, entityName, entityCharacteristicsName, entityCharacteristicType string; triggerKind, outcome VARCHAR(32); endedAt datetime; errorDescription TEXT; status, reason VARCHAR(32); pushId string; commandValue DOUBLE. Indexes `idx_journal_kind_timestamp` (kind, timestamp), `idx_journal_runId` (runId), `idx_journal_kind_title_timestamp` (kind, title, timestamp; the runs of one automation and the distinct automation names) and `idx_journal_kind_place_timestamp` (kind, entityPlaceId, timestamp; the heating commands of a room).

Texts longer than their column are cut by the server to the column width (counted in Unicode scalars, as MySQL counts) before they are written: `journal.title` 255, `journal.detail` 1000, `entityChanges.text` 255. A longer value would fail the insert in strict mode.

A value is one row of `entityChanges`: a number in `number`, a text in `text`, a bool as 1 or 0 in `number`, a deadline as its case in `text` and its end in `number`. How a kind is read back is the `shape` of its `ValueDescriptor`.

Key lengths: an InnoDB index key may be 3072 bytes (DYNAMIC row format) and a utf8mb4 character counts 4 bytes. The code columns (`kind`, `status`, `reason`, `origin`, `triggerKind`, `outcome`, `tokenType`) hold short enum raw values and are VARCHAR(16) or VARCHAR(32), so every index stays far below the limit. The narrow integer types are spelled out because Fluent maps `.int8` and `.uint8` to INT on MySQL.

## Queries and their indexes

- Newest change per entity (`getAllCurrent`, once at start): a `LATERAL` subquery per directory entry, one backward dive into `idx_entityChanges_entity_timestamp` (needs MySQL 8.0.14+).
- History and the newest changes of an entity: `idx_entityChanges_entity_timestamp`, ordered by `timestamp DESC, id DESC` (the primary key is part of every secondary index, so there is no filesort). A history page that ends on a timestamp shared by several rows can skip the rest of them: the cursor is a timestamp only.
- Retention and the hourly rollup run per entity and in bounded steps, each an exact range on `(entityId, timestamp)`: the raw-row delete in batches of 10 000, the rollup in one transaction per entity and at most one day, so a failed run resumes where it stopped.
- Journal cleanup: one batched delete per kind (5 000 rows a statement) on `idx_journal_kind_timestamp`; a command with a heating reason stays for good.
- Timestamps come back from DATETIME(6) at microsecond precision; the home manager compares them at that precision when it merges memory and database history.

## Migration script notes

What changed in the schema that the script moving the old data must respect:

- `entityChanges.id` is a BIGINT AUTO_INCREMENT: leave it out of the INSERT (the order of insertion is the tiebreak of equal timestamps, so insert each entity's rows oldest first). No other table changed its `id` type; `journal.id` and `runId` stay the UUIDs of the old rows.
- `entities.lastReport` is nullable: leave it out of the INSERT (or set it to the timestamp of the newest change of the entity); the server fills it with the next report. A reader takes the later of it and the newest change's timestamp, so an entity without a value still shows its last change as a report.
- The stored `config` row should hold the built-in automations (`DatabaseCleanup`, `WindowProjection`) when it is copied from an old row; the server stores them once at start when they are missing, unless it could not read the row.
- Collation `utf8mb4_0900_bin` (case- and accent-sensitive): two old rows whose `placeId`, `serviceName` and `characteristicType` differ only in case or accent are now two entities; before they would have collided on the UNIQUE key. Look them up with exact strings.
- Column widths: `kind` 16; `status`, `reason`, `triggerKind`, `outcome`, `origin`, `tokenType` 32; `title` 255 and `detail` 1000 (`journal`) and `entityChanges.text` 255 must be cut to fit (by Unicode scalars) or the insert fails in strict mode.
- A change row needs a `number` or a `text` (CHECK constraint); skip rows with neither.
- Foreign keys are RESTRICT: insert `entities` before `entityChanges` and `entityHourlyAggregates`; delete in the opposite order.
- The weather columns are DOUBLE instead of FLOAT; copy the values as they are.
- Timestamps are UTC with at most 6 fractional digits.
- The migration creates all indexes on the empty tables; for a very large import, loading first and building the secondary indexes afterwards is faster, but the final index set must be the one listed above.

## Moving data from the old schema

The old tables `entityItems` (wide, one column per characteristic), `automationRuns`, `heatingWrites` and `fireplaceSwitches` are not part of the schema.

- Old `entityItems` rows become `entities` plus `entityChanges` rows (`number` or `text` per characteristic).
- Old `automationRuns` rows become `journal` rows with kind `run`: id and runId are the old id, timestamp is startedAt, title is automationName, detail is the trigger summary, entityPlaceId and entityName are the trigger's place and name, entityCharacteristicsName and entityCharacteristicType are the trigger's, plus triggerKind, outcome, endedAt and errorDescription.

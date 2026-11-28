# Database schema

The server's MySQL schema is created by one migration, `InitialSchema` in `Sources/Server/Migrations/01_InitialSchema.swift`
(`ServerMigrations.all` is the list; `configure.swift` and the MySQL tests register it). A new database starts from it. The data of
an old database is moved over by a separate script, never by a migration.

MySQL types: every `id` is a UUID primary key; `string` is VARCHAR(255); `datetime` is DATETIME(6); `double` is DOUBLE; `bool` is BOOL.

## Tables

- `deviceToken`: id; deviceName string NOT NULL; tokenString VARCHAR(500) NOT NULL; tokenType string NOT NULL; activityType string; createdAt datetime; updatedAt datetime.
- `config`: id; json LONGBLOB NOT NULL; updatedAt datetime.
- `weatherHours`: primary key (locationKey, hour); locationKey VARCHAR(64) NOT NULL; hour datetime NOT NULL; fetchedAt datetime NOT NULL; temperature2mC, apparentTemperatureC, dewPoint2mC, precipitationMm, windSpeed10mKmh, shortwaveRadiationWm2, directRadiationWm2, diffuseRadiationWm2, directNormalIrradianceWm2, sunshineDurationS FLOAT; relativeHumidity2mPercent, cloudCoverPercent TINYINT UNSIGNED; windDirection10mDeg SMALLINT UNSIGNED; isDay bool.
- `entityHourlyAggregates`: primary key (entityId, hourStart); entityId UUID NOT NULL, foreign key to `entities.id` (cascade delete); hourStart datetime NOT NULL; minValue, meanValue, maxValue, lastValue DOUBLE NOT NULL; valueCount INT NOT NULL.
- `entities` (`EntityDbItem`): id; placeId, serviceName, characteristicType string NOT NULL; characteristicsName string; UNIQUE (placeId, serviceName, characteristicType).
- `entityChanges` (`EntityChangeDbItem`): id; entityId UUID NOT NULL, foreign key to `entities.id` ON DELETE CASCADE; timestamp datetime NOT NULL; number DOUBLE; text string; origin string NOT NULL DEFAULT 'homekit'. Indexes `idx_entityChanges_entity_timestamp` (entityId, timestamp) and `idx_entityChanges_timestamp` (timestamp).
- `journal` (`JournalDbItem`): id; kind string NOT NULL (`run`, `command`, `push`); timestamp datetime NOT NULL; runId UUID; title string NOT NULL; detail VARCHAR(1000) NOT NULL; entityPlaceId, entityName, entityCharacteristicsName, entityCharacteristicType, triggerKind, outcome string; endedAt datetime; errorDescription TEXT; status string; reason string; pushId string; commandValue DOUBLE. Indexes `idx_journal_kind_timestamp` (kind, timestamp), `idx_journal_runId` (runId), `idx_journal_title_timestamp` (title, timestamp).

A value is one row of `entityChanges`: a number in `number`, a text in `text`, a bool as 1 or 0 in `number`, a deadline as its case in `text` and its end in `number`. How a kind is read back is the `shape` of its `ValueDescriptor`.

Key lengths: a key over 3 × VARCHAR(255) utf8mb4 (3060 bytes) plus a DATETIME(6) (8 bytes) fits InnoDB's 3072 bytes (DYNAMIC row format); a fourth string column would not. The narrow integer types are spelled out because Fluent maps `.int8` and `.uint8` to INT on MySQL.

## Moving data from the old schema

The old tables `entityItems` (wide, one column per characteristic), `automationRuns`, `heatingWrites` and `fireplaceSwitches` are not part of the schema. `scripts/migrate-old-database/migrate.sh [--check] <dump.sql.gz> <db-container>` moves their data from a dump of the old database (as `backup.sh` in the config repo writes it) into a new database the server has created: it loads the old tables as `legacy_*`, runs `migrate.sql` in one transaction and drops them again. `--check` prints the report and rolls back. Every row keeps its old id, so a second run adds nothing. `scripts/migrate-old-database/test/test.sh` tests it against two throwaway MySQL containers.

- Old `entityItems` rows become `entities` plus `entityChanges` rows: the value is the column of the row's type (`number`, a color as the text "red green blue"); origin `homekit`, `ValveJob` for valve position and temperature offset. Rows of a type the new schema lacks, or without a value of their type, are left out and counted in the report. An entity gets its newest name.
- Old `entityHourlyAggregates` rows (keyed by place, service and type) point to the entity id.
- Old `fireplaceSwitches` rows become changes of the server-owned switch `server/fireplace` with origin `app`.
- Old `heatingWrites`: the plan target becomes changes of the server-owned `server/<room>/targetTemperature` with origin `server` (one per value change, not one per radiator); a write that reached the radiator (`sentToDevice`) becomes a `journal` row with kind `command`, its reason and value.
- Old `automationRuns` rows become `journal` rows with kind `run`: id and runId are the old id, timestamp is startedAt, title is automationName, detail is the trigger summary, entityPlaceId and entityName are the trigger's place and name, entityCharacteristicsName and entityCharacteristicType are the trigger's, plus triggerKind, outcome (`running` becomes `interrupted`), endedAt and errorDescription.
- `deviceToken` and `weatherHours` are copied as they are; `config` is not (deploy the config again).

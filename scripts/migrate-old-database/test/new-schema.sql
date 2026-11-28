-- The new schema as InitialSchema (Sources/Server/Migrations/01_InitialSchema.swift) creates it with Fluent's MySQL
-- types. Keep in step with that migration; the real server is the reference.
CREATE TABLE deviceToken (id VARBINARY(16) PRIMARY KEY, deviceName VARCHAR(255) NOT NULL, tokenString VARCHAR(500) NOT NULL,
    tokenType VARCHAR(32) NOT NULL, activityType VARCHAR(255), createdAt DATETIME(6), updatedAt DATETIME(6))
    COLLATE utf8mb4_0900_bin;
CREATE TABLE config (id VARBINARY(16) PRIMARY KEY, json LONGBLOB NOT NULL, updatedAt DATETIME(6));
CREATE TABLE weatherHours (locationKey VARCHAR(64) NOT NULL, hour DATETIME(6) NOT NULL, fetchedAt DATETIME(6) NOT NULL,
    temperature2mC DOUBLE, apparentTemperatureC DOUBLE, relativeHumidity2mPercent TINYINT UNSIGNED, dewPoint2mC DOUBLE,
    precipitationMm DOUBLE, cloudCoverPercent TINYINT UNSIGNED, windSpeed10mKmh DOUBLE, windDirection10mDeg SMALLINT UNSIGNED,
    shortwaveRadiationWm2 DOUBLE, directRadiationWm2 DOUBLE, diffuseRadiationWm2 DOUBLE, directNormalIrradianceWm2 DOUBLE,
    sunshineDurationS DOUBLE, isDay BOOL, PRIMARY KEY (locationKey, hour)) COLLATE utf8mb4_0900_bin;
CREATE TABLE entities (id VARBINARY(16) PRIMARY KEY, placeId VARCHAR(255) NOT NULL, serviceName VARCHAR(255) NOT NULL,
    characteristicType VARCHAR(255) NOT NULL, characteristicsName VARCHAR(255),
    UNIQUE KEY (placeId, serviceName, characteristicType)) COLLATE utf8mb4_0900_bin;
CREATE TABLE entityHourlyAggregates (entityId VARBINARY(16) NOT NULL, hourStart DATETIME(6) NOT NULL, minValue DOUBLE NOT NULL,
    meanValue DOUBLE NOT NULL, `maxValue` DOUBLE NOT NULL, lastValue DOUBLE NOT NULL, valueCount BIGINT NOT NULL,
    PRIMARY KEY (entityId, hourStart), FOREIGN KEY (entityId) REFERENCES entities (id) ON DELETE RESTRICT);
CREATE TABLE entityChanges (id BIGINT AUTO_INCREMENT PRIMARY KEY, entityId VARBINARY(16) NOT NULL, timestamp DATETIME(6) NOT NULL,
    number DOUBLE, text VARCHAR(255), origin VARCHAR(32) NOT NULL DEFAULT 'homekit',
    INDEX idx_entityChanges_entity_timestamp (entityId, timestamp), INDEX idx_entityChanges_timestamp_entity (timestamp, entityId),
    CONSTRAINT fk_entityChanges_entityId FOREIGN KEY (entityId) REFERENCES entities (id) ON DELETE RESTRICT,
    CONSTRAINT chk_entityChanges_value CHECK (number IS NOT NULL OR text IS NOT NULL)) COLLATE utf8mb4_0900_bin;
CREATE TABLE journal (id VARBINARY(16) PRIMARY KEY, kind VARCHAR(16) NOT NULL, timestamp DATETIME(6) NOT NULL, runId VARBINARY(16),
    title VARCHAR(255) NOT NULL, detail VARCHAR(1000) NOT NULL, entityPlaceId VARCHAR(255), entityName VARCHAR(255),
    entityCharacteristicsName VARCHAR(255), entityCharacteristicType VARCHAR(255), triggerKind VARCHAR(32), outcome VARCHAR(32),
    endedAt DATETIME(6), errorDescription TEXT, status VARCHAR(32), reason VARCHAR(32), pushId VARCHAR(255), commandValue DOUBLE,
    INDEX idx_journal_kind_timestamp (kind, timestamp), INDEX idx_journal_runId (runId),
    INDEX idx_journal_kind_title_timestamp (kind, title, timestamp),
    INDEX idx_journal_kind_place_timestamp (kind, entityPlaceId, timestamp)) COLLATE utf8mb4_0900_bin;
CREATE TABLE _fluent_migrations (id VARBINARY(16) PRIMARY KEY, name VARCHAR(255) NOT NULL, batch BIGINT NOT NULL,
    created_at DATETIME(6), updated_at DATETIME(6));

-- The new server already ran a little before the migration: it knows the kitchen lamp and stored one change.
INSERT INTO entities VALUES (UNHEX('aa000000000000000000000000000001'), 'Kueche', 'Lampe', 'switcher', NULL);
INSERT INTO entityChanges (entityId, timestamp, number, text, origin)
    VALUES (UNHEX('aa000000000000000000000000000001'), '2026-11-28 08:00:00', 0, NULL, 'homekit');

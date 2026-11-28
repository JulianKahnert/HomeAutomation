-- The new schema as InitialSchema (Sources/Server/Migrations/01_InitialSchema.swift) creates it with Fluent's MySQL
-- types. Keep in step with that migration; the real server is the reference.
CREATE TABLE deviceToken (id VARBINARY(16) PRIMARY KEY, deviceName VARCHAR(255) NOT NULL, tokenString VARCHAR(500) NOT NULL,
    tokenType VARCHAR(255) NOT NULL, activityType VARCHAR(255), createdAt DATETIME(6), updatedAt DATETIME(6));
CREATE TABLE config (id VARBINARY(16) PRIMARY KEY, json LONGBLOB NOT NULL, updatedAt DATETIME(6));
CREATE TABLE weatherHours (locationKey VARCHAR(64) NOT NULL, hour DATETIME(6) NOT NULL, fetchedAt DATETIME(6) NOT NULL,
    temperature2mC FLOAT, apparentTemperatureC FLOAT, relativeHumidity2mPercent TINYINT UNSIGNED, dewPoint2mC FLOAT,
    precipitationMm FLOAT, cloudCoverPercent TINYINT UNSIGNED, windSpeed10mKmh FLOAT, windDirection10mDeg SMALLINT UNSIGNED,
    shortwaveRadiationWm2 FLOAT, directRadiationWm2 FLOAT, diffuseRadiationWm2 FLOAT, directNormalIrradianceWm2 FLOAT,
    sunshineDurationS FLOAT, isDay BOOL, PRIMARY KEY (locationKey, hour));
CREATE TABLE entities (id VARBINARY(16) PRIMARY KEY, placeId VARCHAR(255) NOT NULL, serviceName VARCHAR(255) NOT NULL,
    characteristicType VARCHAR(255) NOT NULL, characteristicsName VARCHAR(255),
    UNIQUE KEY (placeId, serviceName, characteristicType));
CREATE TABLE entityHourlyAggregates (entityId VARBINARY(16) NOT NULL, hourStart DATETIME(6) NOT NULL, minValue DOUBLE NOT NULL,
    meanValue DOUBLE NOT NULL, `maxValue` DOUBLE NOT NULL, lastValue DOUBLE NOT NULL, valueCount BIGINT NOT NULL,
    PRIMARY KEY (entityId, hourStart), FOREIGN KEY (entityId) REFERENCES entities (id) ON DELETE CASCADE);
CREATE TABLE entityChanges (id VARBINARY(16) PRIMARY KEY, entityId VARBINARY(16) NOT NULL, timestamp DATETIME(6) NOT NULL,
    number DOUBLE, text VARCHAR(255), origin VARCHAR(255) NOT NULL DEFAULT 'homekit',
    FOREIGN KEY (entityId) REFERENCES entities (id) ON DELETE CASCADE,
    INDEX idx_entityChanges_entity_timestamp (entityId, timestamp), INDEX idx_entityChanges_timestamp (timestamp));
CREATE TABLE journal (id VARBINARY(16) PRIMARY KEY, kind VARCHAR(255) NOT NULL, timestamp DATETIME(6) NOT NULL, runId VARBINARY(16),
    title VARCHAR(255) NOT NULL, detail VARCHAR(1000) NOT NULL, entityPlaceId VARCHAR(255), entityName VARCHAR(255),
    entityCharacteristicsName VARCHAR(255), entityCharacteristicType VARCHAR(255), triggerKind VARCHAR(255), outcome VARCHAR(255),
    endedAt DATETIME(6), errorDescription TEXT, status VARCHAR(255), reason VARCHAR(255), pushId VARCHAR(255), commandValue DOUBLE,
    INDEX idx_journal_kind_timestamp (kind, timestamp), INDEX idx_journal_runId (runId), INDEX idx_journal_title_timestamp (title, timestamp));
CREATE TABLE _fluent_migrations (id VARBINARY(16) PRIMARY KEY, name VARCHAR(255) NOT NULL, batch BIGINT NOT NULL,
    created_at DATETIME(6), updated_at DATETIME(6));

-- The new server already ran a little before the migration: it knows the kitchen lamp and stored one change.
INSERT INTO entities VALUES (UNHEX('aa000000000000000000000000000001'), 'Kueche', 'Lampe', 'switcher', NULL);
INSERT INTO entityChanges VALUES (UNHEX('aa000000000000000000000000000002'), UNHEX('aa000000000000000000000000000001'), '2026-11-28 08:00:00', 0, NULL, 'homekit');

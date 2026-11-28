-- The old schema as migrations 01 to 12 on develop left it (Fluent's MySQL types), with a few rows of every kind.
CREATE TABLE entityItems (
    id VARBINARY(16) PRIMARY KEY, timestamp DATETIME(6) NOT NULL,
    entityPlaceId VARCHAR(255) NOT NULL, entityServiceName VARCHAR(255) NOT NULL,
    entityCharacteristicsName VARCHAR(255), entityCharacteristicType VARCHAR(255) NOT NULL,
    motionDetected BOOL, illuminanceInLux DOUBLE, isDeviceOn BOOL, isContactOpen BOOL, isDoorLocked BOOL,
    stateOfCharge BIGINT, isHeaterActive BOOL,
    brightness BIGINT, colorTemperature FLOAT, colorRed FLOAT, colorGreen FLOAT, colorBlue FLOAT,
    temperatureInC DOUBLE, relativeHumidity DOUBLE, carbonDioxideSensorId BIGINT, pmDensity DOUBLE, airQuality BIGINT,
    valveOpen BOOL, targetTemperatureInC DOUBLE, heatingMode TINYINT, valvePositionPercent TINYINT UNSIGNED,
    temperatureCalibrationInC DOUBLE,
    INDEX idx_entityItems_entity_timestamp (entityPlaceId, entityServiceName, entityCharacteristicType, timestamp)
);
CREATE TABLE deviceToken (id VARBINARY(16) PRIMARY KEY, deviceName VARCHAR(255) NOT NULL, tokenString VARCHAR(500) NOT NULL,
    tokenType VARCHAR(255) NOT NULL, activityType VARCHAR(255), createdAt DATETIME(6), updatedAt DATETIME(6));
CREATE TABLE config (id VARBINARY(16) PRIMARY KEY, json LONGBLOB NOT NULL, updatedAt DATETIME(6));
CREATE TABLE automationRuns (id VARBINARY(16) PRIMARY KEY, automationName VARCHAR(255) NOT NULL, startedAt DATETIME(6) NOT NULL,
    endedAt DATETIME(6), triggerKind VARCHAR(255) NOT NULL, triggerPlaceId VARCHAR(255), triggerName VARCHAR(255),
    triggerCharacteristicsName VARCHAR(255), triggerCharacteristicType VARCHAR(255), triggerSummary VARCHAR(1000) NOT NULL,
    outcome VARCHAR(255) NOT NULL, errorDescription TEXT);
CREATE TABLE weatherHours (locationKey VARCHAR(64) NOT NULL, hour DATETIME(6) NOT NULL, fetchedAt DATETIME(6) NOT NULL,
    temperature2mC FLOAT, apparentTemperatureC FLOAT, relativeHumidity2mPercent TINYINT UNSIGNED, dewPoint2mC FLOAT,
    precipitationMm FLOAT, cloudCoverPercent TINYINT UNSIGNED, windSpeed10mKmh FLOAT, windDirection10mDeg SMALLINT UNSIGNED,
    shortwaveRadiationWm2 FLOAT, directRadiationWm2 FLOAT, diffuseRadiationWm2 FLOAT, directNormalIrradianceWm2 FLOAT,
    sunshineDurationS FLOAT, isDay BOOL, PRIMARY KEY (locationKey, hour));
CREATE TABLE entityHourlyAggregates (entityPlaceId VARCHAR(255) NOT NULL, entityServiceName VARCHAR(255) NOT NULL,
    entityCharacteristicType VARCHAR(255) NOT NULL, hourStart DATETIME(6) NOT NULL, minValue DOUBLE NOT NULL,
    meanValue DOUBLE NOT NULL, `maxValue` DOUBLE NOT NULL, lastValue DOUBLE NOT NULL, valueCount BIGINT NOT NULL,
    PRIMARY KEY (entityPlaceId, entityServiceName, entityCharacteristicType, hourStart));
CREATE TABLE heatingWrites (id VARBINARY(16) PRIMARY KEY, timestamp DATETIME(6) NOT NULL, placeId VARCHAR(255) NOT NULL,
    name VARCHAR(255) NOT NULL, characteristicsName VARCHAR(255), characteristicType VARCHAR(255) NOT NULL,
    reason VARCHAR(255) NOT NULL, actionName VARCHAR(255) NOT NULL, isActive BOOL, targetTemperatureInC DOUBLE,
    planTargetInC DOUBLE, sentToDevice BOOL NOT NULL);
CREATE TABLE fireplaceSwitches (id VARBINARY(16) PRIMARY KEY, timestamp DATETIME(6) NOT NULL, isOn BOOL NOT NULL);
CREATE TABLE _fluent_migrations (id VARBINARY(16) PRIMARY KEY, name VARCHAR(255) NOT NULL, batch BIGINT NOT NULL,
    created_at DATETIME(6), updated_at DATETIME(6));

-- Ids: 0x01.. entityItems, 0x02.. runs, 0x03.. heating writes, 0x04.. fireplace, 0x05 token.
INSERT INTO entityItems (id, timestamp, entityPlaceId, entityServiceName, entityCharacteristicsName, entityCharacteristicType,
    motionDetected, illuminanceInLux, isDeviceOn, isContactOpen, brightness, colorTemperature, colorRed, colorGreen, colorBlue,
    temperatureInC, carbonDioxideSensorId, heatingMode, valvePositionPercent, temperatureCalibrationInC, targetTemperatureInC) VALUES
    (UNHEX('01000000000000000000000000000001'), '2026-11-20 10:00:00.123456', 'Flur', 'Eve Motion', 'Bewegung alt', 'motionSensor',
        1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (UNHEX('01000000000000000000000000000002'), '2026-11-21 10:00:00', 'Flur', 'Eve Motion', 'Bewegung', 'motionSensor',
        0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (UNHEX('01000000000000000000000000000003'), '2026-11-21 10:00:01', 'Flur', 'Eve Motion', NULL, 'lightSensor',
        NULL, 59.27, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (UNHEX('01000000000000000000000000000004'), '2026-11-21 11:00:00', 'Kueche', 'Lampe', NULL, 'switcher',
        NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (UNHEX('01000000000000000000000000000005'), '2026-11-21 11:00:00', 'Kueche', 'Lampe', NULL, 'brightness',
        NULL, NULL, NULL, NULL, 80, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (UNHEX('01000000000000000000000000000006'), '2026-11-21 11:00:00', 'Kueche', 'Lampe', NULL, 'colorTemperature',
        NULL, NULL, NULL, NULL, NULL, 0.5, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (UNHEX('01000000000000000000000000000007'), '2026-11-21 11:00:00', 'Kueche', 'Lampe', NULL, 'color',
        NULL, NULL, NULL, NULL, NULL, NULL, 1, 0.5, 0.25, NULL, NULL, NULL, NULL, NULL, NULL),
    (UNHEX('01000000000000000000000000000008'), '2026-11-21 12:00:00', 'Bad OG', 'Fenster', NULL, 'contactSensor',
        NULL, NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (UNHEX('01000000000000000000000000000009'), '2026-11-21 12:00:00', 'Bad OG', 'Eve Thermo', NULL, 'temperatureSensor',
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 21.4, NULL, NULL, NULL, NULL, NULL),
    (UNHEX('0100000000000000000000000000000a'), '2026-11-21 12:00:00', 'Bad OG', 'Eve Thermo', NULL, 'heatingMode',
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 1, NULL, NULL, NULL),
    (UNHEX('0100000000000000000000000000000b'), '2026-11-21 12:00:00', 'Bad OG', 'Eve Thermo', NULL, 'valvePosition',
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 35, NULL, NULL),
    (UNHEX('0100000000000000000000000000000c'), '2026-11-21 12:00:00', 'Bad OG', 'Eve Thermo', NULL, 'temperatureCalibration',
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, -1.5, NULL),
    (UNHEX('0100000000000000000000000000000d'), '2026-11-21 12:00:00', 'Bad OG', 'Eve Thermo', NULL, 'targetTemperature',
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 21),
    (UNHEX('0100000000000000000000000000000e'), '2026-11-21 13:00:00', 'Kinderzimmer', 'Luft', NULL, 'carbonDioxideSensorId',
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 812, NULL, NULL, NULL, NULL),
    -- a row without a value of its type and a row of a type the new schema does not know
    (UNHEX('0100000000000000000000000000000f'), '2026-11-21 13:00:00', 'Kueche', 'Lampe', NULL, 'switcher',
        NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    (UNHEX('01000000000000000000000000000010'), '2026-11-21 13:00:00', 'Kueche', 'Alt', NULL, 'obsoleteType',
        NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    -- differs from 'Kueche' only in case: one entity in the old collation, two in the new binary one
    (UNHEX('01000000000000000000000000000011'), '2026-11-21 14:00:00', 'kueche', 'Lampe', NULL, 'switcher',
        NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
    -- a color temperature written as FLOAT keeps its short decimal
    (UNHEX('01000000000000000000000000000012'), '2026-11-21 14:00:00', 'Kueche', 'Lampe', NULL, 'colorTemperature',
        NULL, NULL, NULL, NULL, NULL, 0.3, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL);

INSERT INTO automationRuns VALUES
    (UNHEX('02000000000000000000000000000001'), 'motion-at-night-flur', '2026-11-21 10:00:00', '2026-11-21 10:05:00', 'entityChange',
        'Flur', 'Eve Motion', 'Bewegung', 'motionSensor', 'Flur Eve Motion motion: true', 'completed', NULL),
    (UNHEX('02000000000000000000000000000002'), 'room-heating-bad-og', '2026-11-27 23:59:00', NULL, 'time',
        NULL, NULL, NULL, NULL, '06:00', 'running', NULL);

INSERT INTO heatingWrites VALUES
    -- a plan switch point written to two radiators of one room: one plan target change, two commands
    (UNHEX('03000000000000000000000000000001'), '2026-11-21 06:00:00.100', 'Bad OG', 'Eve Thermo', NULL, 'targetTemperature',
        'plan', 'setTargetTemperature', NULL, 21, 21, 1),
    (UNHEX('03000000000000000000000000000002'), '2026-11-21 06:00:00.200', 'Bad OG', 'Eve Thermo 2', NULL, 'targetTemperature',
        'plan', 'setTargetTemperature', NULL, 21, 21, 1),
    -- a window write, no plan target
    (UNHEX('03000000000000000000000000000003'), '2026-11-21 12:00:05', 'Bad OG', 'Eve Thermo', NULL, 'heating',
        'window', 'setHeating', 0, NULL, NULL, 1),
    -- the room was off at the next switch point: plan target recorded only
    (UNHEX('03000000000000000000000000000004'), '2026-11-21 22:00:00', 'Bad OG', 'Eve Thermo', NULL, 'targetTemperature',
        'plan', 'setTargetTemperature', NULL, 17.5, 17.5, 0);

INSERT INTO fireplaceSwitches VALUES
    (UNHEX('04000000000000000000000000000001'), '2026-11-21 18:00:00', 1),
    (UNHEX('04000000000000000000000000000002'), '2026-11-21 22:00:00', 0);

INSERT INTO entityHourlyAggregates VALUES ('Flur', 'Eve Motion', 'lightSensor', '2026-08-01 10:00:00', 1, 2, 3, 2.5, 12);
INSERT INTO weatherHours (locationKey, hour, fetchedAt, temperature2mC, isDay) VALUES ('oldenburg', '2026-11-21 10:00:00', '2026-11-21 09:00:00', 4.5, 1);
INSERT INTO deviceToken VALUES (UNHEX('05000000000000000000000000000001'), 'iPhone', 'abc', 'pushNotification', NULL, '2026-10-01 00:00:00', NULL);
INSERT INTO config VALUES (UNHEX('06000000000000000000000000000001'), '{}', NULL);

-- Moves the data of the old schema into the new one (docs/database-schema.md, "Moving data from the old schema").
-- Runs in the new database after migrate.sh loaded the old tables under the prefix `legacy_`, converted to the
-- binary collation of the new schema, so names match exactly as in Swift.
-- Re-runnable: journal rows keep the UUID of their old row and skip a duplicate with ON DUPLICATE KEY UPDATE
-- (which, unlike INSERT IGNORE, still fails on a bad value); entities match on their unique key; an entity change
-- (BIGINT id of its own) is left out when the entity already has a change at that exact timestamp.
-- migrate.sh ends the transaction opened below with COMMIT, or ROLLBACK for --check, and drops the legacy_ tables.

-- Setup before the transaction, since DDL would commit it. Plain tables, not TEMPORARY ones: MySQL cannot open a
-- temporary table twice in one query (the report does).

-- The old characteristic types the new CharacteristicsType still has; rows of any other type are left out.
DROP TABLE IF EXISTS legacy_knownTypes;
CREATE TABLE legacy_knownTypes (name VARCHAR(255) PRIMARY KEY) COLLATE utf8mb4_0900_bin;
INSERT INTO legacy_knownTypes VALUES
    ('motionSensor'), ('lightSensor'), ('batterySensor'), ('contactSensor'),
    ('temperatureSensor'), ('relativeHumiditySensor'), ('carbonDioxideSensorId'), ('pmDensitySensor'), ('airQualitySensor'),
    ('switcher'), ('brightness'), ('colorTemperature'), ('color'), ('valve'),
    ('lock'), ('heating'), ('targetTemperature'), ('heatingMode'), ('valvePosition'), ('temperatureCalibration');

-- The value of each old row of a known type: it sits in the column of its type (one value per row, as the old
-- adapter wrote it). A Bool becomes 1 or 0, a color the text "red green blue". The Eve valve values came from the
-- adapter's poller; their origin is now the ValveJob, like new rows of these types. A FLOAT goes through its
-- shortest text, so 0.3 stays 0.3 in the DOUBLE column instead of 0.30000001192092896.
DROP TABLE IF EXISTS legacy_values;
CREATE TABLE legacy_values (
    INDEX (entityPlaceId, entityServiceName, entityCharacteristicType)
) COLLATE utf8mb4_0900_bin AS
SELECT o.id, o.timestamp, o.entityPlaceId, o.entityServiceName, o.entityCharacteristicsName, o.entityCharacteristicType,
       CASE o.entityCharacteristicType
           WHEN 'motionSensor' THEN o.motionDetected
           WHEN 'lightSensor' THEN o.illuminanceInLux
           WHEN 'batterySensor' THEN o.stateOfCharge
           WHEN 'contactSensor' THEN o.isContactOpen
           WHEN 'temperatureSensor' THEN o.temperatureInC
           WHEN 'relativeHumiditySensor' THEN o.relativeHumidity
           WHEN 'carbonDioxideSensorId' THEN o.carbonDioxideSensorId
           WHEN 'pmDensitySensor' THEN o.pmDensity
           WHEN 'airQualitySensor' THEN o.airQuality
           WHEN 'switcher' THEN o.isDeviceOn
           WHEN 'brightness' THEN o.brightness
           WHEN 'colorTemperature' THEN CAST(CAST(o.colorTemperature AS CHAR) AS DOUBLE)
           WHEN 'valve' THEN o.valveOpen
           WHEN 'lock' THEN o.isDoorLocked
           WHEN 'heating' THEN o.isHeaterActive
           WHEN 'targetTemperature' THEN o.targetTemperatureInC
           WHEN 'heatingMode' THEN o.heatingMode
           WHEN 'valvePosition' THEN o.valvePositionPercent
           WHEN 'temperatureCalibration' THEN o.temperatureCalibrationInC
       END AS number,
       CASE WHEN o.entityCharacteristicType = 'color'
            THEN CONCAT(o.colorRed, ' ', o.colorGreen, ' ', o.colorBlue)
       END AS text,
       CASE WHEN o.entityCharacteristicType IN ('valvePosition', 'temperatureCalibration')
            THEN 'ValveJob' ELSE 'homekit'
       END AS origin
FROM legacy_entityItems o
JOIN legacy_knownTypes k ON k.name = o.entityCharacteristicType;

START TRANSACTION;

-- 1. entities: one row per place, service and type that has a value, with the newest name seen.
INSERT INTO entities (id, placeId, serviceName, characteristicType, characteristicsName)
SELECT UUID_TO_BIN(UUID()), entityPlaceId, entityServiceName, entityCharacteristicType, entityCharacteristicsName
FROM (
    SELECT entityPlaceId, entityServiceName, entityCharacteristicType, entityCharacteristicsName,
           ROW_NUMBER() OVER (PARTITION BY entityPlaceId, entityServiceName, entityCharacteristicType
                              ORDER BY timestamp DESC) AS newest
    FROM legacy_values
    WHERE number IS NOT NULL OR text IS NOT NULL
) named
WHERE newest = 1
ON DUPLICATE KEY UPDATE id = entities.id;

-- 2. entityChanges, oldest first per entity: the auto-increment id is the tiebreak of equal timestamps.
INSERT INTO entityChanges (entityId, timestamp, number, text, origin)
SELECT e.id, v.timestamp, v.number, v.text, v.origin
FROM legacy_values v
JOIN entities e ON e.placeId = v.entityPlaceId
               AND e.serviceName = v.entityServiceName
               AND e.characteristicType = v.entityCharacteristicType
WHERE (v.number IS NOT NULL OR v.text IS NOT NULL)
  AND NOT EXISTS (SELECT 1 FROM entityChanges c WHERE c.entityId = e.id AND c.timestamp = v.timestamp)
ORDER BY e.id, v.timestamp, v.id;

-- 3. entityHourlyAggregates: the old key (place, service, type) becomes the entity id.
INSERT INTO entityHourlyAggregates (entityId, hourStart, minValue, meanValue, `maxValue`, lastValue, valueCount)
SELECT e.id, a.hourStart, a.minValue, a.meanValue, a.`maxValue`, a.lastValue, a.valueCount
FROM legacy_entityHourlyAggregates a
JOIN entities e ON e.placeId = a.entityPlaceId
               AND e.serviceName = a.entityServiceName
               AND e.characteristicType = a.entityCharacteristicType
ON DUPLICATE KEY UPDATE entityId = entityHourlyAggregates.entityId;

-- 4. The fireplace: `fireplaceSwitches` becomes the changes of the server-owned switch (Fireplace.stateId),
-- which the app set (origin app).
INSERT INTO entities (id, placeId, serviceName, characteristicType, characteristicsName)
SELECT UUID_TO_BIN(UUID()), 'server', 'fireplace', 'switcher', NULL
FROM DUAL
WHERE EXISTS (SELECT 1 FROM legacy_fireplaceSwitches)
ON DUPLICATE KEY UPDATE id = entities.id;

INSERT INTO entityChanges (entityId, timestamp, number, text, origin)
SELECT e.id, f.timestamp, f.isOn, NULL, 'app'
FROM legacy_fireplaceSwitches f
JOIN entities e ON e.placeId = 'server' AND e.serviceName = 'fireplace' AND e.characteristicType = 'switcher'
WHERE NOT EXISTS (SELECT 1 FROM entityChanges c WHERE c.entityId = e.id AND c.timestamp = f.timestamp)
ORDER BY f.timestamp, f.id;

-- 5. The plan target per room: `heatingWrites.planTargetInC` becomes the changes of the server-owned entity
-- (server, <room>, targetTemperature) that RoomHeating reports now. Every radiator of a room carried the same
-- plan target, so only a value that differs from the room's previous one is a change.
INSERT INTO entities (id, placeId, serviceName, characteristicType, characteristicsName)
SELECT UUID_TO_BIN(UUID()), 'server', placeId, 'targetTemperature', NULL
FROM (SELECT DISTINCT placeId FROM legacy_heatingWrites WHERE planTargetInC IS NOT NULL) rooms
ON DUPLICATE KEY UPDATE id = entities.id;

INSERT INTO entityChanges (entityId, timestamp, number, text, origin)
SELECT e.id, p.timestamp, p.planTargetInC, NULL, 'server'
FROM (
    SELECT id, placeId, timestamp, planTargetInC,
           LAG(planTargetInC) OVER (PARTITION BY placeId ORDER BY timestamp, id) AS previous
    FROM legacy_heatingWrites
    WHERE planTargetInC IS NOT NULL
) p
JOIN entities e ON e.placeId = 'server' AND e.serviceName = p.placeId AND e.characteristicType = 'targetTemperature'
WHERE (p.previous IS NULL OR p.previous <> p.planTargetInC)
  AND NOT EXISTS (SELECT 1 FROM entityChanges c WHERE c.entityId = e.id AND c.timestamp = p.timestamp)
ORDER BY p.timestamp, p.id;

-- 6. Radiator writes become journal commands with their reason; the journal cleanup keeps them for good.
-- A write that never reached the radiator (sentToDevice = 0) was only a plan target and is in step 5.
INSERT INTO journal (id, kind, timestamp, runId, title, detail,
                     entityPlaceId, entityName, entityCharacteristicsName, entityCharacteristicType,
                     status, reason, commandValue)
SELECT h.id, 'command', h.timestamp, NULL, h.actionName,
       CASE h.actionName
           WHEN 'setHeating' THEN CONCAT('setHeating(active: ', IF(h.isActive, 'true', 'false'), ')')
           -- Swift prints a whole Double with ".0"
           ELSE CONCAT('setTargetTemperature(celsius: ', h.targetTemperatureInC,
                       IF(h.targetTemperatureInC = FLOOR(h.targetTemperatureInC), '.0', ''), ')')
       END,
       h.placeId, h.name, h.characteristicsName, h.characteristicType,
       'executed', h.reason,
       CASE h.actionName WHEN 'setHeating' THEN h.isActive ELSE h.targetTemperatureInC END
FROM legacy_heatingWrites h
WHERE h.sentToDevice = 1
ON DUPLICATE KEY UPDATE id = journal.id;

-- 7. Automation runs become journal runs. A run still "running" in the old database ended with that server.
INSERT INTO journal (id, kind, timestamp, runId, title, detail,
                     entityPlaceId, entityName, entityCharacteristicsName, entityCharacteristicType,
                     triggerKind, outcome, endedAt, errorDescription)
SELECT r.id, 'run', r.startedAt, r.id, r.automationName, r.triggerSummary,
       r.triggerPlaceId, r.triggerName, r.triggerCharacteristicsName, r.triggerCharacteristicType,
       r.triggerKind, IF(r.outcome = 'running', 'interrupted', r.outcome), r.endedAt, r.errorDescription
FROM legacy_automationRuns r
ON DUPLICATE KEY UPDATE id = journal.id;

-- 8. Tables with the same columns in both schemas: push tokens (so the app need not register again) and weather.
INSERT INTO deviceToken (id, deviceName, tokenString, tokenType, activityType, createdAt, updatedAt)
SELECT id, deviceName, tokenString, tokenType, activityType, createdAt, updatedAt
FROM legacy_deviceToken
ON DUPLICATE KEY UPDATE id = deviceToken.id;

INSERT INTO weatherHours (locationKey, hour, fetchedAt, temperature2mC, apparentTemperatureC, relativeHumidity2mPercent,
                          dewPoint2mC, precipitationMm, cloudCoverPercent, windSpeed10mKmh, windDirection10mDeg,
                          shortwaveRadiationWm2, directRadiationWm2, diffuseRadiationWm2, directNormalIrradianceWm2,
                          sunshineDurationS, isDay)
SELECT locationKey, hour, fetchedAt, temperature2mC, apparentTemperatureC, relativeHumidity2mPercent,
       dewPoint2mC, precipitationMm, cloudCoverPercent, windSpeed10mKmh, windDirection10mDeg,
       shortwaveRadiationWm2, directRadiationWm2, diffuseRadiationWm2, directNormalIrradianceWm2,
       sunshineDurationS, isDay
FROM legacy_weatherHours
ON DUPLICATE KEY UPDATE locationKey = weatherHours.locationKey;

-- Report: what the old database had, what the new one holds now, and what was left out and why.
SELECT 'entityItems rows' AS what, (SELECT COUNT(*) FROM legacy_entityItems) AS old, NULL AS new
UNION ALL SELECT 'entityItems rows of an unknown type',
    (SELECT COUNT(*) FROM legacy_entityItems o LEFT JOIN legacy_knownTypes k ON k.name = o.entityCharacteristicType WHERE k.name IS NULL), NULL
UNION ALL SELECT 'entityItems rows without a value of their type',
    (SELECT COUNT(*) FROM legacy_values WHERE number IS NULL AND text IS NULL), NULL
UNION ALL SELECT 'entities (old: place, service, type)',
    (SELECT COUNT(*) FROM (SELECT DISTINCT entityPlaceId, entityServiceName, entityCharacteristicType FROM legacy_values
                           WHERE number IS NOT NULL OR text IS NOT NULL) d),
    (SELECT COUNT(*) FROM entities)
UNION ALL SELECT 'entityChanges', NULL, (SELECT COUNT(*) FROM entityChanges)
UNION ALL SELECT 'entityHourlyAggregates', (SELECT COUNT(*) FROM legacy_entityHourlyAggregates), (SELECT COUNT(*) FROM entityHourlyAggregates)
UNION ALL SELECT 'fireplace switches', (SELECT COUNT(*) FROM legacy_fireplaceSwitches),
    (SELECT COUNT(*) FROM entityChanges c JOIN entities e ON e.id = c.entityId
     WHERE e.placeId = 'server' AND e.serviceName = 'fireplace' AND e.characteristicType = 'switcher')
UNION ALL SELECT 'plan target changes', (SELECT COUNT(*) FROM legacy_heatingWrites WHERE planTargetInC IS NOT NULL),
    (SELECT COUNT(*) FROM entityChanges c JOIN entities e ON e.id = c.entityId
     WHERE e.placeId = 'server' AND e.characteristicType = 'targetTemperature')
UNION ALL SELECT 'heating commands (sent to the radiator)', (SELECT COUNT(*) FROM legacy_heatingWrites WHERE sentToDevice = 1),
    (SELECT COUNT(*) FROM journal WHERE kind = 'command' AND reason IS NOT NULL)
UNION ALL SELECT 'automation runs', (SELECT COUNT(*) FROM legacy_automationRuns), (SELECT COUNT(*) FROM journal WHERE kind = 'run')
UNION ALL SELECT 'device tokens', (SELECT COUNT(*) FROM legacy_deviceToken), (SELECT COUNT(*) FROM deviceToken)
UNION ALL SELECT 'weather hours', (SELECT COUNT(*) FROM legacy_weatherHours), (SELECT COUNT(*) FROM weatherHours);


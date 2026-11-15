# Weather hours

`OutdoorTemperatureJob` fetches the Open-Meteo forecast once an hour and upserts one row per hour into `weatherHours` (migration 08). Each response holds 72 hours (`past_days=1`, `forecast_days=2`), so every hour is written several times: the newest fetch wins, and a past hour ends with the observed value instead of an old forecast. Nothing deletes these rows (one location is about 8,760 rows and 1.6 MB per year); there is no HTTP endpoint, read them with SQL.

| Column | Open-Meteo variable | Unit |
|---|---|---|
| `locationKey` | `latitude,longitude` as configured | |
| `hour` | `time`, start of the hour | UTC |
| `fetchedAt` | time of the fetch that last wrote the row | UTC |
| `temperature2mC` | `temperature_2m` | °C |
| `apparentTemperatureC` | `apparent_temperature` | °C |
| `relativeHumidity2mPercent` | `relative_humidity_2m` | % |
| `dewPoint2mC` | `dew_point_2m` | °C |
| `precipitationMm` | `precipitation` (preceding hour) | mm |
| `cloudCoverPercent` | `cloud_cover` | % |
| `windSpeed10mKmh` | `wind_speed_10m` | km/h |
| `windDirection10mDeg` | `wind_direction_10m` | ° |
| `shortwaveRadiationWm2` | `shortwave_radiation` (preceding hour mean) | W/m² |
| `directRadiationWm2` | `direct_radiation` (preceding hour mean) | W/m² |
| `diffuseRadiationWm2` | `diffuse_radiation` (preceding hour mean) | W/m² |
| `directNormalIrradianceWm2` | `direct_normal_irradiance` (preceding hour mean) | W/m² |
| `sunshineDurationS` | `sunshine_duration` (preceding hour) | s |
| `isDay` | `is_day` | 0/1 |

The primary key `(locationKey, hour)` is the upsert key and serves range queries per location.

## Read

Last 48 hours of one location:

```sql
SELECT hour, temperature2mC, cloudCoverPercent, shortwaveRadiationWm2
FROM weatherHours
WHERE locationKey = 'LAT,LON' AND hour BETWEEN UTC_TIMESTAMP() - INTERVAL 48 HOUR AND UTC_TIMESTAMP()
ORDER BY hour;
```

Daily mean, minimum and maximum outdoor temperature:

```sql
SELECT DATE(hour) AS day, AVG(temperature2mC) AS meanC, MIN(temperature2mC) AS minC, MAX(temperature2mC) AS maxC
FROM weatherHours
WHERE locationKey = 'LAT,LON'
GROUP BY DATE(hour)
ORDER BY day;
```

Outdoor temperature next to a thermostat's valve position (same UTC hour):

```sql
SELECT e.timestamp, e.valvePositionPercent, w.temperature2mC
FROM entityItems e
JOIN weatherHours w
  ON w.locationKey = 'LAT,LON'
 AND w.hour = TIMESTAMP(DATE_FORMAT(e.timestamp, '%Y-%m-%d %H:00:00'))
WHERE e.entityPlaceId = 'Kueche' AND e.entityCharacteristicType = 'valvePosition'
ORDER BY e.timestamp DESC
LIMIT 100;
```

## Backfill from the archive

The archive API (`archive-api.open-meteo.com/v1/archive`) returns the same `hourly` format. Use your own latitude and longitude; the `locationKey` must be the same string the server uses (`latitude,longitude` exactly as configured).

```bash
curl -s "https://archive-api.open-meteo.com/v1/archive?latitude=LAT&longitude=LON&start_date=2026-06-01&end_date=2026-10-31&hourly=temperature_2m,apparent_temperature,relative_humidity_2m,dew_point_2m,precipitation,cloud_cover,wind_speed_10m,wind_direction_10m,shortwave_radiation,direct_radiation,diffuse_radiation,direct_normal_irradiance,sunshine_duration,is_day&timezone=UTC" -o archive.json
```

Set `@json` to the file's contents (paste it, or `LOAD_FILE` with `secure_file_priv`), then upsert it; existing hours are overwritten like by a fetch, and JSON `null` becomes SQL `NULL`:

```sql
INSERT INTO weatherHours (locationKey, hour, fetchedAt, temperature2mC, apparentTemperatureC, relativeHumidity2mPercent, dewPoint2mC, precipitationMm, cloudCoverPercent, windSpeed10mKmh, windDirection10mDeg, shortwaveRadiationWm2, directRadiationWm2, diffuseRadiationWm2, directNormalIrradianceWm2, sunshineDurationS, isDay)
SELECT * FROM (
  SELECT 'LAT,LON' AS locationKey, STR_TO_DATE(t.time, '%Y-%m-%dT%H:%i') AS hour, UTC_TIMESTAMP(6) AS fetchedAt,
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(@json, CONCAT('$.hourly.temperature_2m[', t.i - 1, ']'))), 'null') AS temperature2mC,
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(@json, CONCAT('$.hourly.apparent_temperature[', t.i - 1, ']'))), 'null') AS apparentTemperatureC,
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(@json, CONCAT('$.hourly.relative_humidity_2m[', t.i - 1, ']'))), 'null') AS relativeHumidity2mPercent,
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(@json, CONCAT('$.hourly.dew_point_2m[', t.i - 1, ']'))), 'null') AS dewPoint2mC,
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(@json, CONCAT('$.hourly.precipitation[', t.i - 1, ']'))), 'null') AS precipitationMm,
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(@json, CONCAT('$.hourly.cloud_cover[', t.i - 1, ']'))), 'null') AS cloudCoverPercent,
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(@json, CONCAT('$.hourly.wind_speed_10m[', t.i - 1, ']'))), 'null') AS windSpeed10mKmh,
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(@json, CONCAT('$.hourly.wind_direction_10m[', t.i - 1, ']'))), 'null') AS windDirection10mDeg,
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(@json, CONCAT('$.hourly.shortwave_radiation[', t.i - 1, ']'))), 'null') AS shortwaveRadiationWm2,
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(@json, CONCAT('$.hourly.direct_radiation[', t.i - 1, ']'))), 'null') AS directRadiationWm2,
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(@json, CONCAT('$.hourly.diffuse_radiation[', t.i - 1, ']'))), 'null') AS diffuseRadiationWm2,
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(@json, CONCAT('$.hourly.direct_normal_irradiance[', t.i - 1, ']'))), 'null') AS directNormalIrradianceWm2,
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(@json, CONCAT('$.hourly.sunshine_duration[', t.i - 1, ']'))), 'null') AS sunshineDurationS,
    NULLIF(JSON_UNQUOTE(JSON_EXTRACT(@json, CONCAT('$.hourly.is_day[', t.i - 1, ']'))), 'null') AS isDay
  FROM JSON_TABLE(@json, '$.hourly.time[*]' COLUMNS (i FOR ORDINALITY, time VARCHAR(16) PATH '$')) t
) AS a
ON DUPLICATE KEY UPDATE
  temperature2mC = a.temperature2mC,
  apparentTemperatureC = a.apparentTemperatureC,
  relativeHumidity2mPercent = a.relativeHumidity2mPercent,
  dewPoint2mC = a.dewPoint2mC,
  precipitationMm = a.precipitationMm,
  cloudCoverPercent = a.cloudCoverPercent,
  windSpeed10mKmh = a.windSpeed10mKmh,
  windDirection10mDeg = a.windDirection10mDeg,
  shortwaveRadiationWm2 = a.shortwaveRadiationWm2,
  directRadiationWm2 = a.directRadiationWm2,
  diffuseRadiationWm2 = a.diffuseRadiationWm2,
  directNormalIrradianceWm2 = a.directNormalIrradianceWm2,
  sunshineDurationS = a.sunshineDurationS,
  isDay = a.isDay,
  fetchedAt = a.fetchedAt;
```

Never run this against production without a backup.

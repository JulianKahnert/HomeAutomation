# Weather snapshots

`OutdoorTemperatureJob` fetches the Open-Meteo forecast once an hour and stores the complete JSON response as one row of `weatherSnapshots` (`id`, `locationKey` = `latitude,longitude`, `fetchedAt`, `json` LONGTEXT). Each response holds 72 hours (`past_days=1`, `forecast_days=2`), so consecutive snapshots overlap on purpose: a gap in one fetch is covered by the next. Nothing deletes these rows (about 70 MB per year); there is no HTTP endpoint, read them with SQL. The queries are untested drafts for MySQL 9.

## Read snapshots

Latest snapshot per location:

```sql
SELECT s.locationKey, s.fetchedAt, s.json
FROM weatherSnapshots s
JOIN (SELECT locationKey, MAX(fetchedAt) AS fetchedAt FROM weatherSnapshots GROUP BY locationKey) l
  ON l.locationKey = s.locationKey AND l.fetchedAt = s.fetchedAt;
```

One variable per hour of the latest snapshot:

```sql
SELECT t.hour, t.temperature_2m, t.shortwave_radiation
FROM weatherSnapshots s,
     JSON_TABLE(s.json, '$.hourly' COLUMNS (
       NESTED PATH '$.time[*]' COLUMNS (idx FOR ORDINALITY, hour VARCHAR(16) PATH '$'),
       temperature_2m DOUBLE PATH '$.temperature_2m[0]',
       shortwave_radiation DOUBLE PATH '$.shortwave_radiation[0]')) t
WHERE s.id = (SELECT id FROM weatherSnapshots ORDER BY fetchedAt DESC LIMIT 1);
```

The simple way for one hour: find its index in `$.hourly.time` and extract the same index.

```sql
SELECT s.fetchedAt,
       JSON_EXTRACT(s.json, CONCAT('$.hourly.temperature_2m[',
         JSON_UNQUOTE(JSON_SEARCH(s.json, 'one', '2026-11-14T12:00', NULL, '$.hourly.time[*]')) , ']')) AS dummy
FROM weatherSnapshots s LIMIT 1;
```

If the path gymnastics get annoying, take the index in a client instead: `time` is hourly from the first element, so for the hour `H` the index is the hours between `$.hourly.time[0]` and `H`.

## Backfill from the archive

The archive API (`archive-api.open-meteo.com/v1/archive`) returns the same `hourly` format, so a day of archive data is a valid snapshot. One row per day is enough. Use your own latitude and longitude; the `locationKey` must be the same string the server uses (`latitude,longitude` exactly as configured).

```bash
curl -s "https://archive-api.open-meteo.com/v1/archive?latitude=LAT&longitude=LON&start_date=2026-06-01&end_date=2026-06-01&hourly=temperature_2m,apparent_temperature,relative_humidity_2m,dew_point_2m,precipitation,cloud_cover,wind_speed_10m,wind_direction_10m,shortwave_radiation,direct_radiation,diffuse_radiation,direct_normal_irradiance,sunshine_duration,is_day&timezone=UTC" -o day.json
```

Store it with `fetchedAt` set to the end of that day, so a real snapshot of the same hours (fetched later) sorts after it:

```sql
INSERT INTO weatherSnapshots (id, locationKey, fetchedAt, json)
VALUES (UNHEX(REPLACE(UUID(), '-', '')), 'LAT,LON', '2026-06-01 23:59:59', '<contents of day.json>');
```

Loop over June to October with a shell loop over the dates. Check the `id` column type with `DESCRIBE weatherSnapshots` first (Fluent creates UUIDs as `BINARY(16)`), and never run this against production without a backup.

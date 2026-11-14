# Weather backfill

The server stores one `weatherHours` row per (location, hour) from the hourly `OutdoorTemperatureJob`. Older hours come from the Open-Meteo archive API, which uses the same `hourly` format as the forecast API, so `OutdoorTemperatureJob.parseHours` reads it unchanged. Use your own latitude and longitude.

```bash
curl -s "https://archive-api.open-meteo.com/v1/archive?latitude=LAT&longitude=LON&start_date=2026-06-01&end_date=2026-10-31&hourly=temperature_2m,apparent_temperature,relative_humidity_2m,dew_point_2m,precipitation,cloud_cover,wind_speed_10m,wind_direction_10m,shortwave_radiation,direct_radiation,diffuse_radiation,direct_normal_irradiance,sunshine_duration,is_day&timezone=UTC" -o weather-archive.json
```

There is no importer yet: feeding `weather-archive.json` through `parseHours` and `WeatherHourDbRepository.upsert` is a follow-up. Do not run it against production without a backup.

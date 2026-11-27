# Setup Server

## Prerequisites

If using the "EnergyLowPrice" automation, you need to change the Tibber API key with the URL "https://api.tibber.com/v1-beta/gql".
It will be set automatically when the automation runs for the first time.


## Setup

```
# build server (again)
docker-compose build

# start in background
docker-compose up -d

# stop
docker-compose down
```

## Environment variables

| Variable | Required | Notes |
|---|---|---|
| `AUTH_TOKEN` | yes | Bearer token for all HTTP endpoints incl. the adapter WebSocket. Generate with `openssl rand -base64 32`. |
| `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USERNAME` | no | Default to the docker-compose values. |
| `DATABASE_PASSWORD` | yes (release) | Release builds refuse to start without it; DEBUG builds fall back to the docker-compose default. |
| `DATABASE_TLS_VERIFY` | no | `true` enables full TLS certificate verification for the MySQL connection. Off by default because the stock MySQL image uses a self-signed certificate; turn it on whenever the database is not on a private container network. A warning is logged while it is off. |
| `PUSH_NOTIFICATION_*` | yes (release) | APNS key material, see `docker-compose.yml` in the config repository. |
| `TZ` | no | Time zone used for time-based automations. |
| `LOG_LEVEL` | no | `trace` … `critical`. Defaults to `notice` with `--env production` (the Docker image), else `info`. |
| `HA_DEBUG_LOGGING` | no | `1`/`true` lowers the log level to `debug` (a `trace` level stays), e.g. to see each stored thermostat value (`Stored heating entity item`). Off by default. |

Never commit real values of these variables. Keep them in a git-ignored `.env` file and reference them from `docker-compose.yml` as `${AUTH_TOKEN}` etc.

## Other Commands

```
# only start db
docker-compose up db

# set log level
LOG_LEVEL=trace docker-compose up app

# debug logs on top of the configured level
HA_DEBUG_LOGGING=1 docker-compose up app

# run migration (the server also migrates on start; a new, empty database gets the one initial schema)
docker-compose run migrate

# show logs
docker ps
docker logs <CONTAINER_ID>

# Build & run Swift Ubuntu container locally
docker run -it --workdir /code -v ${PWD}:/code swift:6.0-noble /bin/bash

swift build
TZ=Europe/Berlin swift run Server serve
TZ=Europe/Berlin swift run Server serve
```

## MySQL tests

`EntityStorageMySQLTests` run only against a throwaway MySQL (`HA_TEST_MYSQL_PORT` set); without it they are skipped, so `swift test` does not cover the MySQL-only queries (the journal cleanup, the narrow storage). `scripts/run-mysql-tests.sh [git-ref]` runs them with Docker alone: it starts `mysql:9` and builds and tests inside the Swift image of the Dockerfile's build stage (`swift:6.4-noble`; keep the two tags equal). The log goes to `mysql-tests.log`. Never point the tests at a real database: they create and fill the tables.

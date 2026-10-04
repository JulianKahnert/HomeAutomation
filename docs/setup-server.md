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

Never commit real values of these variables. Keep them in a git-ignored `.env` file and reference them from `docker-compose.yml` as `${AUTH_TOKEN}` etc.

## Other Commands

```
# only start db
docker-compose up db

# set log level
LOG_LEVEL=trace docker-compose up app

# run migration
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

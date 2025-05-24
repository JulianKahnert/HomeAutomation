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

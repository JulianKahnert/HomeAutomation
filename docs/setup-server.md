# Setup Server

## Prerequisits

If using the "EnergyLowPrice" automation, you need change the tibber api key with the URL "https://api.tibber.com/v1-beta/gql".
It will be set automatically when the automations runs the first time.


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
docker compose run migrate

# show logs
docker container ls
docker logs CONTAINER_ID

# build & run swift ubuntu container locally
docker run -it -v ${PWD}:/code swift:6.0-noble /bin/bash

cd /code
TZ=Europe/Berlin swift run Server serve
```

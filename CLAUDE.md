# Claude Code Development Guide

## Architecture Overview

```
┌──────────────┐  WebSocket (StarActor  ┌──────────────┐   REST/OpenAPI   ┌──────────────┐
│   Adapter    │◄──System, port 8080)──►│    Server     │◄───(port 8080)──►│  Controller  │
│  (HomeKit)   │     /adapter/v1        │   (Vapor)     │                  │  (iOS app)   │
└──────┬───────┘                        └──────┬────────┘                  └──────────────┘
       │                                       │
   HomeKit API                            MySQL + APNS
```

- **Server** — Vapor app (runs as Docker container, Swift 6.2, Ubuntu Noble, jemalloc). HTTP API (OpenAPI), MySQL persistence, database migrations, scheduled jobs, APNS push notifications, automations engine. Configured via [HomeAutomation-config-template](https://github.com/JulianKahnert/HomeAutomation-config-template).
- **Adapter** (FlowKit Adapter / HomeKitAdapterApp) — Bridges HomeKit entities to the Server via the in-repo `StarActorSystem` (distributed actors over an authenticated WebSocket, `/adapter/v1` on port 8080; see docs/adr-001). No business logic; reads HomeKit characteristics and forwards state.
- **Controller** (FlowKit Controller) — iOS app using TCA (The Composable Architecture). Activates/deactivates automations, shows switched devices, entity state history charts, window Live Activities. Communicates with Server via generated OpenAPI client.

## Build Commands

### Swift Package (Server/Library)
```bash
swift build
```

### FlowKitAdapter (iOS App)
```bash
cd Apps/FlowKitAdapter
xcodebuild -project "FlowKit Adapter.xcodeproj" -scheme "FlowKit Adapter" -sdk iphonesimulator -configuration Debug build
```

**Note**: After creating new Swift files in `Apps/FlowKitAdapter/`, you must add them to the Xcode project manually using Xcode or update the `.pbxproj` file.

### FlowKitController (iOS App)
```bash
cd Apps/FlowKitController
xcodebuild -project "FlowKit Controller.xcodeproj" -scheme "FlowKit Controller" -sdk iphonesimulator -configuration Debug build
```

## Local Development with Docker

Docker Compose starts the server and MySQL database for local development.

### Setup

Docker Compose configuration is in a separate repository:
**https://github.com/JulianKahnert/HomeAutomation-config-template**

```bash
# Clone the config repository (if not already done)
git clone https://github.com/JulianKahnert/HomeAutomation-config-template.git

# Start services
docker-compose up -d
```

This starts:
- **app** - HomeAutomation server (port 8080)
- **db** - MySQL 9 database (port 3306)
- **migrate** - Database migration service (manual activation)

### Database Connection Details

- **Host**: `db` (inside Docker network only)
- **Port**: 3306
- **Database**: `vapor_database`
- **Username**: `vapor_username`
- **Password**: `vapor_password`

### Debugging Database

Access the MySQL database directly:

```bash
# Connect to the database
docker exec -it homeautomation-config-template-db-1 mysql -u vapor_username -pvapor_password vapor_database

# Useful commands
SHOW TABLES;
DESCRIBE entityItems;
SELECT * FROM entityItems ORDER BY timestamp DESC LIMIT 10;
```

View application and database logs:

```bash
# Application logs
docker logs -f homeautomation-config-template-app-1

# Database logs
docker logs -f homeautomation-config-template-db-1
```

### Authentication

The Vapor HTTP server (port 8080) requires token-based authentication for all endpoints.

#### Configuration

```bash
# Generate a secure random token
openssl rand -base64 32

# Set in environment
export AUTH_TOKEN="your-secure-token-here"
```

#### Making Authenticated Requests

Use the standard HTTP `Authorization` header with Bearer token:

```bash
curl -H "Authorization: Bearer your-token-here" http://localhost:8080/config
```

#### Debugging Without Authentication

⚠️ **DEBUG BUILDS ONLY** - Disable authentication for local testing:

```bash
export AUTH_DISABLED=true
```

This should NEVER be used in production deployments.

#### Docker Compose Setup

Update your `docker-compose.yml`:

```yaml
services:
  app:
    environment:
      - AUTH_TOKEN=${AUTH_TOKEN}
```

Create/update `.env` file:
```bash
AUTH_TOKEN=your-secure-token-here
```

## Project Structure

### SPM Modules (`Sources/`)

- `Server` — Vapor executable: HTTP API (OpenAPI), database, migrations, scheduled jobs, APNS
- `Adapter` — HomeKit bridge, distributed actors for Server communication
- `Controller` — TCA features, views, Live Activities for FlowKit Controller
- `ServerClient` — Generated OpenAPI client for Controller → Server communication
- `HAModels` — Shared domain models (entities, automations, storage items)
- `HAApplicationLayer` — HomeManager, AutomationService
- `HAImplementations` — Concrete automations (14 types), Tibber integration
- `Shared` — Logging, distributed actor system, utilities

### Apps (`Apps/`)

- `FlowKitAdapter/` — Xcode project for HomeKit Adapter iOS/macOS app
- `FlowKitController/` — Xcode project for Controller iOS app + widget extension
- `HomeKitAdapterApp/` — Alternative adapter app target

### Tests (`Tests/`)

- `SharedTests`, `HomeAutomationKitTests`, `ControllerTests`, `ServerTests`

### Other

- `Dockerfile` — Multi-stage Docker build (Swift 6.2, Ubuntu Noble, jemalloc)
- `openapi.yaml` — OpenAPI spec; both `Server` and `ServerClient` use `swift-openapi-generator`

## Model layers

### Model Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ EntityStorageItem (Domain Model)                            │
│ - Full entity with EntityId                                 │
│ - Type-safe (Measurement<T>, RGB struct)                    │
│ - Used in: Adapter, HomeManager, Automations                │
│ File: Sources/HAModels/EntityStorageItem.swift              │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│ EntityStorageDbItem (Database/ORM Model)                    │
│ - Fluent model with @Field wrappers                         │
│ - Direct database schema mapping                            │
│ - Used in: EntityStorageDbRepository                        │
│ File: Sources/Server/Models/EntityStorageDbItem.swift       │
└─────────────────────┬───────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────┐
│ EntityHistoryItem (API/Transport Model)                     │
│ - Lightweight, no EntityId                                  │
│ - Simple types (Double, Int) for JSON                       │
│ - Used in: OpenAPI responses, iOS UI                        │
│ File: Sources/HAModels/EntityHistoryItem.swift              │
└─────────────────────────────────────────────────────────────┘
```

## CI / GitHub Actions

PR checks run on `main` and `develop` branches (`.github/workflows/pr-checks.yml`):

- **Swift Package Build & Test** — `swift build` + `swift test` on macOS
- **iOS Apps Build** — Matrix build of FlowKitAdapter and FlowKitController (includes Package.resolved freshness check)
- **Docker Build** — Builds the Server Docker image on Ubuntu

Additional workflows: `docker-publish.yaml` (amd64 + arm64 image for pushes to `develop`/`main` and for release tags, which also get a GitHub Release), `renovate-package-resolved.yaml` (dependency updates).

## Where things are

- [CODING_STANDARDS.md](CODING_STANDARDS.md): the code rules (security, pre-commit checks, Git flow, adding entity fields), the shared ones linked from it and this repo's own. Read it before writing code.
- `docs/setup-FlowKitAdapter.md` — Adapter setup: launchctl, iOS guided access, logging
- `docs/setup-server.md` — Server Docker setup, log levels, migration
- More on how the features work: the project's folder in the knowledge base (the Obsidian vault), under `references/`. Without the vault (a cloud session, CI), go on without it.

## Common Issues

### "Cannot find [Type] in scope" in Xcode build

**Cause**: New Swift files not added to Xcode project

**Solution**: Open the `.xcodeproj` in Xcode and add the files to the target, or manually edit the `.pbxproj` file

### Build works with `swift build` but fails with `xcodebuild`

**Cause**: Xcode projects have separate build configuration from SPM

**Solution**: Ensure all dependencies are properly linked in Xcode project settings

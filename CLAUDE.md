# Claude Code Development Guide

## Table of Contents

1. [Overview & Architecture](#overview--architecture)
2. [Build Commands](#build-commands)
3. [Project Structure](#project-structure)
4. [Core Domain Models](#core-domain-models)
5. [Automation System](#automation-system)
6. [Device Abstraction Layer](#device-abstraction-layer)
7. [Application Layer Architecture](#application-layer-architecture)
8. [Server Architecture](#server-architecture)
9. [iOS Applications](#ios-applications)
10. [Testing Approach](#testing-approach)
11. [Local Development with Docker](#local-development-with-docker)
12. [Git Workflow](#git-workflow)
13. [Database & API Schema Updates](#database--api-schema-updates)
14. [Pre-Commit Checklist](#pre-commit-checklist)
15. [Key Conventions & Patterns](#key-conventions--patterns)
16. [Dependencies](#dependencies)
17. [Common Issues](#common-issues)
18. [Quick Reference](#quick-reference)

---

## Overview & Architecture

**FlowKit** is a distributed home automation system that enables writing testable HomeKit automations in Swift that run 24/7 on a server, independent of iOS devices.

### System Architecture

```
HomeKit Devices ↔ FlowKit Adapter (iOS/macOS App)
                  ↓↑ (WebSocket/Distributed Actors)
              FlowKit Server (Vapor)
              ↓ (Global Actor)
         Your Swift Automations
              ↓↑
         MySQL Database
```

The system uses **Swift Distributed Actors** for async communication between the adapter and server, enabling remote procedure calls across process boundaries.

### Design Principles

- **Type Safety**: Leverage Swift's type system for compile-time safety
- **Testability**: All automations are testable without physical HomeKit devices
- **Separation of Concerns**: Clear boundaries between domain, application, and infrastructure layers
- **Protocol-Oriented**: Heavy use of protocols for decoupling and flexibility
- **Actor-Based Concurrency**: Thread-safe state management with Swift actors

---

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

**Note**: After creating new Swift files in `Apps/FlowKitAdapter/Views/`, you must add them to the Xcode project manually using Xcode or update the `.pbxproj` file.

### FlowKitController (iOS App)
```bash
cd Apps/FlowKitController
xcodebuild -project "FlowKit Controller.xcodeproj" -scheme "FlowKit Controller" -sdk iphonesimulator -configuration Debug build
```

---

## Project Structure

```
/home/user/HomeAutomation/
├── Sources/
│   ├── HAModels/              # Domain models (shared, no dependencies)
│   ├── HAImplementations/      # Built-in automations & device implementations
│   ├── HAApplicationLayer/     # Business logic (HomeManager, AutomationService)
│   ├── Adapter/                # HomeKit adapter (distributed actor)
│   ├── Controller/             # iOS management app (TCA architecture)
│   ├── Server/                 # Vapor web server
│   ├── ServerClient/           # OpenAPI client for iOS
│   └── Shared/                 # Utilities, distributed actors, logging
├── Apps/
│   ├── FlowKitAdapter/         # HomeKit bridge iOS/macOS app
│   └── FlowKitController/      # Management & monitoring iOS app
├── Tests/
│   ├── HomeAutomationKitTests/
│   ├── ServerTests/
│   ├── ControllerTests/
│   └── SharedTests/
├── Package.swift               # Swift Package Manager manifest
├── openapi.yaml               # OpenAPI spec for server API
└── Dockerfile                 # Server deployment
```

### Swift Modules & Responsibilities

| Module | Purpose | Key Types |
|--------|---------|-----------|
| **HAModels** | Domain models, protocols, core data structures (no dependencies) | `EntityId`, `EntityStorageItem`, `HomeManagable`, `Automatable`, `HomeEvent` |
| **HAApplicationLayer** | Business logic orchestration | `HomeManager`, `AutomationService`, `ActionLogManager`, `WindowManager` |
| **HAImplementations** | Pre-built automations & entity types | `MotionAtNight`, `SetLightProperties`, `GardenWatering`, device classes |
| **Shared** | Cross-platform utilities | `Cache<K,V>`, `Timer`, `CustomActorSystem`, logging infrastructure |
| **Adapter** | HomeKit bridge implementation | `HomeKitAdapter`, `HomeKitCommandReceiver` (distributed actor) |
| **Server** | Vapor-based REST/WebSocket server | Controllers, migrations, jobs, database models |
| **ServerClient** | OpenAPI-generated HTTP client | Generated from `openapi.yaml` |
| **Controller** | iOS management app UI | TCA (Composable Architecture) features, Live Activities |

**Import Graph:** `HAModels` imports nothing from `Sources/`, ensuring it's a pure domain layer. Other modules depend on `HAModels` and `Shared`.

---

## Core Domain Models

### EntityId (Compound Identifier)

Uniquely identifies a home automation entity:
- `placeId`: Room/location identifier
- `name`: Device name
- `characteristicType`: Type of characteristic (e.g., brightness, motion)
- `characteristicsName`: Optional sub-characteristic

**Example:**
```swift
let motionSensor = EntityId(
    placeId: "living-room",
    name: "motion-sensor",
    characteristicType: "motion-detected"
)
```

### EntityStorageItem (Device/Sensor State)

Snapshot of an entity's state at a point in time:
- Core properties: `motionDetected`, `isDeviceOn`, `brightness`, `temperature`, `illuminance`, `color`, etc.
- Stored with timestamp for historical tracking
- Uses type-safe `Measurement` objects (e.g., `Measurement<UnitTemperature>`)
- Supports serialization and reflection-based introspection

**Key Fields:**
```swift
struct EntityStorageItem {
    var entityId: EntityId
    var timestamp: Date

    // State fields
    var motionDetected: Bool?
    var isDeviceOn: Bool?
    var brightness: Double?          // 0.0-1.0
    var colorTemperature: Double?    // 0.0-1.0 (warm to cool)
    var color: RGB?
    var temperatureInC: Measurement<UnitTemperature>?
    var illuminanceInLux: Measurement<UnitIlluminance>?
    var humidityInPercent: Double?
    var co2InPPM: Double?
    var batteryInPercent: Double?
    // ... and more
}
```

### HomeManagable Protocol

Main interface for automations to interact with the home:
```swift
protocol HomeManagable {
    // Get current state of an entity
    func getCurrentEntity(_ entityId: EntityId) async throws -> EntityStorageItem

    // Execute HomeKit commands
    func perform(_ action: HomeAction) async throws

    // Trigger HomeKit scenes
    func trigger(scene: String) async throws

    // Store historical data
    func addEntityHistory(_ item: EntityStorageItem) async throws

    // Send push notifications
    func sendNotification(title: String, message: String) async throws
}
```

### Automatable Protocol

Interface that all automations must implement:
```swift
protocol Automatable: Sendable {
    var isActive: Bool { get }                                    // Enable/disable
    var name: String { get }                                      // Unique name
    var triggerEntityIds: Set<EntityId> { get }                  // Which sensors trigger this

    func shouldTrigger(event: HomeEvent, hm: HomeManagable) async -> Bool  // Decision logic
    func execute(hm: HomeManagable) async throws                           // Action execution
}
```

### HomeEvent (Trigger Events)

Events that trigger automation evaluation:
```swift
enum HomeEvent {
    case change(entity: EntityStorageItem)  // Sensor/device state changed
    case time(date: Date)                   // Time-based trigger (periodic)
    case sunrise                             // Sunrise event
    case sunset                              // Sunset event
}
```

---

## Automation System

### How Automations Work

Automations follow a two-phase execution model:

#### 1. Decision Phase: `shouldTrigger(event:hm:)`
- Called when a trigger entity changes or on schedule
- Asynchronously evaluates whether automation should run
- Can query current state of any entity via `hm.getCurrentEntity()`
- Returns `true` if automation should execute

**Example:**
```swift
func shouldTrigger(event: HomeEvent, hm: HomeManagable) async -> Bool {
    guard case .change(let entity) = event,
          entity.entityId == motionSensor.id else { return false }

    // Motion detected AND it's dark?
    let lightLevel = try? await lightSensor.getIlluminance(with: hm)
    return entity.motionDetected == true && (lightLevel ?? 0) < 60
}
```

#### 2. Execution Phase: `execute(hm:)`
- Called when `shouldTrigger` returns `true`
- Can perform multiple actions in sequence or parallel
- Can include delays with `try await Task.sleep(for: .seconds(60))`
- Use `withTaskGroup` for concurrent operations

**Example:**
```swift
func execute(hm: HomeManagable) async throws {
    // Turn on light immediately
    try await light.turnOn(with: hm)
    try await light.setBrightness(to: 1.0, with: hm)

    // Wait 60 seconds
    try await Task.sleep(for: .seconds(60))

    // Dim and turn off
    try await light.setBrightness(to: 0.2, with: hm)
    try await Task.sleep(for: .seconds(5))
    try await light.turnOff(with: hm)
}
```

### Built-in Automations

| Automation | Purpose |
|------------|---------|
| `MotionAtNight` | Motion-triggered lighting with brightness/color temperature control |
| `SetLightProperties` | Time-based light configuration (circadian lighting) |
| `WindowOpen` | Window state monitoring with notifications |
| `GardenWatering` | Weather-based irrigation control |
| `EnergyLowPrice` | Tibber API integration for price-based device control |
| `Turn` | Simple on/off actions |
| `TurnOnForDuration` | Timed device activation |
| `CreateScene`, `TriggerScene` | HomeKit scene management |
| `HealthCheck`, `RestartSystem` | System maintenance |

### Creating a New Automation

1. Create a struct implementing `Automatable`
2. Add to `AnyAutomation` enum in `Sources/HAModels/AnyAutomation.swift`
3. Register in configuration
4. Write tests if logic is complex

**Template:**
```swift
struct MyAutomation: Automatable {
    let isActive: Bool
    let name: String
    let triggerEntityIds: Set<EntityId>

    // Your custom properties
    let targetDevice: SwitchDevice

    func shouldTrigger(event: HomeEvent, hm: HomeManagable) async -> Bool {
        // Decision logic here
        return true
    }

    func execute(hm: HomeManagable) async throws {
        // Execution logic here
        try await targetDevice.turnOn(with: hm)
    }
}
```

### Automation Lifecycle

1. **Registration**: Automation added to config, loaded by `AutomationService`
2. **Event Subscription**: Service subscribes to events from trigger entities
3. **Event Received**: Entity change or time event occurs
4. **Evaluation**: `shouldTrigger()` called for all active automations
5. **Execution**: If `true`, `execute()` runs in isolated task
6. **Logging**: Actions logged to database for debugging
7. **Notification**: Push notifications sent if configured

---

## Device Abstraction Layer

Device classes provide type-safe, convenient interfaces to entities. They wrap `EntityId` and provide async methods for common operations.

### Base Device Types

| Device Class | Purpose | Key Methods |
|--------------|---------|-------------|
| `SwitchDevice` | On/off control with optional brightness, color temperature, RGB | `turnOn()`, `turnOff()`, `setBrightness()`, `setColorTemperature()`, `setColor()` |
| `MotionSensorDevice` | Motion detection with light sensor and battery | `isMotionDetected()`, `getIlluminance()`, `getBatteryLevel()` |
| `ContactSensorDevice` | Door/window open/close detection | `isContactOpen()`, `getBatteryLevel()` |
| `AirSensorDevice` | Temperature, humidity, CO2, air quality | `getTemperature()`, `getHumidity()`, `getCO2()` |
| `ValveDevice` | Irrigation/heating valve control | `open()`, `close()`, `setPercentage()` |
| `HeatSwitchDevice` | Thermostat control | `setTargetTemperature()`, `getCurrentTemperature()` |

### Concrete Implementations

- **IKEA Lights**: `IkeaLightBulbWhite`, `IkeaLightBulbColored`
- **Eve Devices**: `EveMotion`, `EveThermo`
- **Generic Devices**: `LightBulbDimmable`, `LightBulbColored`, `GenericMotionSensor`
- **Sensors**: `WindowContactSensor`, `TemperatureSensor`

### Usage Pattern

```swift
// Define device in automation
let light = SwitchDevice(
    placeId: "bedroom",
    name: "ceiling-light"
)

// Use in execute()
try await light.turnOn(with: hm)
try await light.setBrightness(to: 0.8, with: hm)
try await light.setColorTemperature(to: 0.3, with: hm)  // Warm

// Query state in shouldTrigger()
let brightness = try await light.getBrightness(with: hm)
let isOn = try await light.isDeviceOn(with: hm)
```

### Normalized Values

All device methods use normalized values (0.0-1.0):
- **Brightness**: 0.0 (off) to 1.0 (full brightness)
- **Color Temperature**: 0.0 (warm/2700K) to 1.0 (cool/6500K)
- **RGB**: Each channel 0.0-1.0
- **Percentage**: 0.0 (0%) to 1.0 (100%)

---

## Application Layer Architecture

### HomeManager (Global Actor)

**File:** `Sources/HAApplicationLayer/HomeManager.swift`

Central orchestrator marked with `@HomeManagerActor` for thread safety.

**Responsibilities:**
- Manages entity state caching (2-hour TTL)
- Executes HomeKit actions with deduplication
- Persists entity history to database asynchronously
- Implements retry logic for failed actions
- Manages window state tracking
- Sends push notifications

**Key Methods:**
```swift
@HomeManagerActor
actor HomeManager: HomeManagable {
    func getCurrentEntity(_ entityId: EntityId) async throws -> EntityStorageItem
    func perform(_ action: HomeAction) async throws
    func trigger(scene: String) async throws
    func addEntityHistory(_ item: EntityStorageItem) async throws
    func sendNotification(title: String, message: String) async throws
}
```

**Caching Strategy:**
- Entities cached for 2 hours to reduce database queries
- Cache invalidated on new entity updates
- Thread-safe access via global actor

### AutomationService (Actor)

**File:** `Sources/HAApplicationLayer/AutomationService.swift`

Evaluates and executes automations in response to events.

**Responsibilities:**
- Subscribes to home events
- Evaluates `shouldTrigger()` for all active automations
- Manages concurrent automation execution
- Prevents duplicate automations from running
- Provides stop/start/disable capabilities

**Event Processing:**
```swift
1. Event received (entity change, time, sun)
2. Filter automations by trigger entity
3. Parallel evaluation of shouldTrigger()
4. Execute automations that returned true
5. Log results and errors
```

### Event Processing Job

**File:** `Sources/Server/Jobs/EventProcessingJob.swift`

Background job that processes home events and runs automations.

**Flow:**
```
HomeKit Device Change
  ↓
HomeKitAdapter (iOS)
  ↓ (Distributed Actor)
HomeEventReceiver (Server)
  ↓
EventProcessingJob
  ↓
AutomationService
  ↓
Automation.execute()
  ↓
HomeManager.perform()
  ↓ (Distributed Actor)
HomeKitCommandReceiver (iOS)
  ↓
HomeKit Framework
  ↓
HomeKit Device
```

---

## Server Architecture

### Technology Stack

- **Framework**: Vapor 4.120.0+
- **Database**: MySQL 9 with Fluent ORM
- **API**: OpenAPI 3.1 with swift-openapi-generator
- **Push Notifications**: APNSwift for APNS
- **Distributed System**: swift-distributed-actors

### Key Files

| File | Purpose |
|------|---------|
| `configure.swift` | Application setup, database, APNS, actor system |
| `routes.swift` | HTTP endpoints and request routing |
| `entrypoint.swift` | Server entry point |
| `Controllers/OpenAPIController.swift` | OpenAPI endpoint handler |

### API Endpoints (OpenAPI)

```
GET    /config                               # Get location & automations config
POST   /config                               # Update configuration with validation
GET    /config/automations                   # List automations with status
POST   /config/automations/{name}/activate   # Enable automation
POST   /config/automations/{name}/deactivate # Disable automation
POST   /config/automations/{name}/stop       # Stop running automation
POST   /pushdevices                          # Register device for notifications
GET    /windowstates                         # Get window open/close status
POST   /windowstates/{id}                    # Set window state
GET    /entity-history/{id}                  # Get historical entity data
POST   /actions                              # Log action execution
```

### Background Jobs

| Job | Purpose | Schedule |
|-----|---------|----------|
| `EventProcessingJob` | Processes home events and runs automations | On event |
| `ClockJob` | Generates periodic time-based events | Every minute |
| `DatabaseCleanupJob` | Deletes old entity history (>2 days) | Periodic |

### Database Schema

**Primary Table:** `entityItems`

Stores historical entity states with:
- Entity metadata (placeId, name, characteristic type)
- Timestamp
- All entity properties (nullable for flexibility)

**Migrations:**
```
Sources/Server/Migrations/
  ├── 01_CreateEntityStorageDbItem.swift
  ├── 02_DeviceTokenItem.swift
  └── 03_AddSensorFields.swift
```

Migrations auto-run on server startup.

### Push Notifications

- **APNS integration** with mock mode for development
- **Device token management** in database
- **Live Activities** for window state updates
- **Environment variables** for certificate/key configuration:
  - `PUSH_NOTIFICATION_PRIVATE_KEY`
  - `PUSH_NOTIFICATION_KEY_IDENTIFIER`
  - `PUSH_NOTIFICATION_TEAM_IDENTIFIER`
  - `ENABLE_APNS_DEBUG`

### Distributed Actors

**Purpose:** Enable remote procedure calls between iOS adapter and server.

**Key Actors:**
- `HomeKitCommandReceiver`: Receives HomeKit commands from iOS adapter
- `HomeEventReceiver`: Receives entity change events from adapter
- `CustomActorSystem`: Custom cluster system configuration

**Configuration:**
```swift
let actorSystem = CustomActorSystem(
    host: "0.0.0.0",
    port: 8888
)
```

---

## iOS Applications

### FlowKitAdapter

**Purpose:** HomeKit bridge that runs on an iOS/macOS device with HomeKit access.

**Capabilities:**
- Communicates with HomeKit framework
- Monitors HomeKit characteristic changes
- Forwards events to server via distributed actors
- Receives commands from server and executes via HomeKit
- Must run in foreground to maintain HomeKit access

**Location:** `Apps/FlowKitAdapter/`

### FlowKitController

**Purpose:** Management and monitoring iOS app for viewing and controlling automations.

**Architecture:** The Composable Architecture (TCA)

**Features:**
- Automation management (enable/disable/stop)
- Entity history visualization with charts
- Live Activities for window state
- Push notification handling
- Settings management
- Configuration editing

**Location:** `Apps/FlowKitController/`

**Key Components:**
- `ServerClient`: OpenAPI-generated API client
- TCA Features: Modular features with state, actions, reducers
- Chart Extensions: Custom chart rendering for entity history
- Widget Extension: Home screen widgets

---

## Testing Approach

### Test Structure

```
Tests/
├── HomeAutomationKitTests/
│   ├── RealworldAutomationTests/
│   │   ├── SetLightPropertiesTests.swift
│   │   └── MotionAtNightTests.swift
│   ├── HelperTests/
│   │   ├── CircadianLightTests.swift
│   │   └── RoundingTests.swift
│   ├── MockHomeAdapter.swift
│   ├── MockStorageRepository.swift
│   └── MockNotificationSender.swift
├── ServerTests/
├── ControllerTests/
└── SharedTests/
```

### Testing Patterns

**Mock Implementations:**
```swift
// Mock HomeManagable for testing
actor MockHomeAdapter: HomeManagable {
    var entities: [EntityId: EntityStorageItem] = [:]
    var performedActions: [HomeAction] = []

    func getCurrentEntity(_ entityId: EntityId) async throws -> EntityStorageItem {
        entities[entityId] ?? EntityStorageItem(entityId: entityId)
    }

    func perform(_ action: HomeAction) async throws {
        performedActions.append(action)
    }
}
```

**Testing Automations:**
```swift
@Test func testMotionAtNightTriggersWhenDark() async throws {
    let hm = MockHomeAdapter()
    let automation = MotionAtNight(...)

    // Setup: Dark environment
    hm.entities[lightSensor.id] = EntityStorageItem(
        entityId: lightSensor.id,
        illuminanceInLux: Measurement(value: 30, unit: .lux)
    )

    // Trigger: Motion detected
    let event = HomeEvent.change(entity: EntityStorageItem(
        entityId: motionSensor.id,
        motionDetected: true
    ))

    // Assert: Should trigger
    let shouldTrigger = await automation.shouldTrigger(event: event, hm: hm)
    #expect(shouldTrigger == true)

    // Execute and verify actions
    try await automation.execute(hm: hm)
    #expect(hm.performedActions.contains { $0.targetEntityId == light.id })
}
```

**Async/Await Testing:**
- Use `async` test functions
- Leverage `@HomeManagerActor` when testing HomeManager
- Test tags with `@Test` attribute for filtering

---

## Local Development with Docker

For local development and testing, the database and application can be started using Docker Compose.

### Setup

The Docker Compose configuration is maintained in a separate repository:
**https://github.com/JulianKahnert/HomeAutomation-config-template**

```bash
# Clone the config repository (if not already done)
git clone https://github.com/JulianKahnert/HomeAutomation-config-template.git

# Start services
docker-compose up -d
```

This starts:
- **app** - HomeAutomation server (ports 8080, 8888)
- **db** - MySQL 9 database (port 3306)
- **migrate** - Database migration service (manual activation)

### Database Connection Details

- **Host**: `db` (inside Docker network) or `localhost` (from host machine)
- **Port**: 3306
- **Database**: `vapor_database`
- **Username**: `vapor_username`
- **Password**: `vapor_password`

### Debugging Database

For debugging purposes, you can directly access the MySQL database:

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

---

## Git Workflow

This project follows the **Git-Flow** branching model:

### Branch Structure

- **`main`** - Production-ready releases only
  - Receives git tags for version releases
  - Never commit directly to this branch

- **`develop`** - Integration branch for features
  - Never work directly on this branch
  - All feature branches merge here via pull requests

### Feature Development

1. **Always branch from `develop`:**
   ```bash
   git checkout develop
   git pull
   git checkout -b feature/<issue-number>-description
   ```

2. **Branch naming convention:**
   - Format: `feature/<issue-number>-description`
   - Example: `feature/99-prevent-server-shutdown`
   - Use lowercase and hyphens for readability

3. **Creating pull requests:**
   - Base branch: `develop` (NOT `main`)
   - Target: Merge your feature branch into `develop`
   - After approval, features are merged to `develop`

4. **Release process:**
   - When ready for release, `develop` is merged to `main`
   - Git tags are created on `main` for version tracking

### Quick Reference

```bash
# Start new feature
git checkout develop && git pull && git checkout -b feature/123-my-feature

# Keep feature branch updated
git checkout develop && git pull && git checkout feature/123-my-feature && git merge develop

# Create PR (always target develop)
gh pr create --base develop --head feature/123-my-feature
```

---

## Database & API Schema Updates

### ⚠️ CRITICAL: When Adding New Entity Fields

When adding new sensor fields or entity properties, you MUST update **all six layers**:

#### 1. Database Migration (REQUIRED)
Create a new migration file in `Sources/Server/Migrations/`:

```bash
# Example: 04_AddNewSensorFields.swift
```

**Template:**
```swift
import Fluent

struct AddNewSensorFields: AsyncMigration {
    func prepare(on database: Database) async throws {
        try await database.schema("entityItems")
            .field("newFieldName", .double)  // or .int, .bool, .string
            .update()
    }

    func revert(on database: Database) async throws {
        try await database.schema("entityItems")
            .deleteField("newFieldName")
            .update()
    }
}
```

**Don't forget to register it in `Sources/Server/configure.swift`:**
```swift
app.migrations.add(AddNewSensorFields())
```

#### 2. Update Database Model
File: `Sources/Server/Models/EntityStorageDbItem.swift`

- Add `@Field` property to the model
- Update `map()` method to convert FROM `EntityStorageItem`
- Update `mapDbItem()` function to convert TO `EntityStorageItem`

#### 3. Update OpenAPI Schema (REQUIRED)
File: `openapi.yaml`

Update the `EntityHistoryItem` schema with ALL fields:
```yaml
EntityHistoryItem:
  type: object
  properties:
    id:
      type: string
      format: uuid
    timestamp:
      type: string
      format: date-time
    newFieldName:  # ADD YOUR NEW FIELD HERE
      type: number
      format: double
      nullable: true
```

#### 4. Update API Response Model
File: `Sources/HAModels/EntityHistoryItem.swift`

- Add the new field as an optional property
- Update the `Codable` mapping if needed

#### 5. Update Chart Display Logic (Optional)
File: `Sources/Controller/Extensions/EntityHistoryItem+Chart.swift`

Add your field to `primaryValue` getter with appropriate priority:
```swift
var primaryValue: Double? {
    if let newField { return newField }  // Add here
    if let temperatureInC { return temperatureInC }
    // ... rest of priority list
}
```

#### 6. Update Server Controller
File: `Sources/Server/Controllers/OpenAPIController.swift`

In `getEntityHistory()`, ensure the field is mapped from `EntityStorageItem` to the OpenAPI response.

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

**When to update each:**
- **EntityStorageItem**: When HomeKit adapter reads new characteristics
- **EntityStorageDbItem**: ALWAYS when adding fields that need persistence
- **EntityHistoryItem**: ALWAYS when fields should appear in history charts

### Migration Checklist

When adding new entity fields, verify ALL of these:

- [ ] Created migration file in `Sources/Server/Migrations/`
- [ ] Registered migration in `Sources/Server/configure.swift`
- [ ] Updated `EntityStorageDbItem` model with `@Field` property
- [ ] Updated `map()` method in EntityStorageDbItem (TO database)
- [ ] Updated `mapDbItem()` function (FROM database)
- [ ] Updated `openapi.yaml` schema with new fields
- [ ] Updated `EntityHistoryItem.swift` with new properties
- [ ] Updated OpenAPIController mapping logic
- [ ] Updated chart display logic (if visualization needed)
- [ ] Tested with `swift build` and app builds

**Example PRs that missed migrations:**
- PR #89: Added entity history but no migration for new fields
- PR #90: Server changes but OpenAPI schema incomplete
- PR #93: ✅ Correct implementation with migration + full schema

---

## Pre-Commit Checklist

Before committing changes that affect iOS apps:

1. Run SwiftLint:
   ```bash
   swiftlint --fix
   ```

2. Build Swift Package:
   ```bash
   swift build
   ```

3. Build affected iOS app(s):
   ```bash
   # For FlowKitAdapter changes
   cd Apps/FlowKitAdapter && xcodebuild -project "FlowKit Adapter.xcodeproj" -scheme "FlowKit Adapter" -sdk iphonesimulator -configuration Debug build

   # For FlowKitController changes
   cd Apps/FlowKitController && xcodebuild -project "FlowKit Controller.xcodeproj" -scheme "FlowKit Controller" -sdk iphonesimulator -configuration Debug build
   ```

4. Ensure all builds pass before committing

---

## Key Conventions & Patterns

### Naming Conventions

- **Automations (type)**: `PascalCase` (e.g., `MotionAtNight`)
- **Automation names (instance)**: `kebab-case` (e.g., "motion-at-night")
- **Entity IDs**: compound format `placeId-device-characteristic`
- **Protocol names**: Suffixed with `-able` (e.g., `Automatable`, `Validatable`)
- **Device classes**: Descriptive names (e.g., `SwitchDevice`, `MotionSensorDevice`)

### Code Organization

- **Clear separation of concerns** across modules
- **Shallow import graphs** (HAModels imports nothing from Sources/)
- **Extensions organized by functionality** (e.g., `EntityHistoryItem+Chart.swift`)
- **Helper/utility files grouped logically**

### Async/Concurrency

- **Heavy use of `async/await`** throughout the codebase
- **Global actors** for thread safety (`@HomeManagerActor`)
- **Distributed actors** for inter-process communication
- **Task groups** for concurrent operations (`withTaskGroup`)

### Error Handling

- **Swift's `throws`** and custom error types
- **Logging with swift-log** framework
- **Log levels**: `.critical`, `.error`, `.warning`, `.info`, `.debug`, `.trace`
- **Assertion failures** for development-only checks

### Reflection & Introspection

- **`Automatable.getEntityIds()`** uses `Mirror` reflection to discover entity IDs
- Allows dynamic configuration validation
- Prevents need to manually list dependencies

### Architecture Patterns

1. **Domain-Driven Design**: Clear separation between domain (HAModels), application (HAApplicationLayer), and infrastructure (Server)
2. **Repository Pattern**: Data access abstraction for entity history
3. **Adapter Pattern**: HomeKit characteristics → domain entities
4. **Factory Pattern**: `AnyAutomation` enum wraps automation types
5. **Protocol-Oriented Programming**: Heavy use of protocols for decoupling
6. **Global Actor Pattern**: `HomeManager` ensures thread safety
7. **Service Layer**: Services for automation, notifications, configuration

---

## Dependencies

### Core Framework Dependencies

```swift
// Web Framework
.package(url: "https://github.com/vapor/vapor.git", from: "4.120.0"),
.package(url: "https://github.com/vapor/fluent.git", from: "4.13.0"),
.package(url: "https://github.com/vapor/fluent-mysql-driver.git", from: "4.8.0"),

// OpenAPI
.package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.10.3"),
.package(url: "https://github.com/swift-server/swift-openapi-vapor.git", from: "1.0.1"),
.package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.9.0"),

// Composable Architecture (iOS)
.package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.23.1"),
.package(url: "https://github.com/pointfreeco/swift-sharing.git", from: "2.7.4"),

// Distributed Actors
.package(url: "https://github.com/apple/swift-distributed-actors.git", revision: "0041f6a"),

// Utilities
.package(url: "https://github.com/pointfreeco/swift-dependencies.git", from: "1.10.0"),
.package(url: "https://github.com/apple/swift-log.git", from: "1.8.0"),
.package(url: "https://github.com/apple/swift-log-oslog.git", from: "0.2.2"),
.package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.1.1"),

// External Integrations
.package(url: "https://github.com/klaaspieter/TibberSwift.git", branch: "main"),  // Energy pricing
.package(url: "https://github.com/swift-server-community/APNSwift.git", from: "6.3.0"),  // Push notifications
```

### Swift Version

- **Minimum**: Swift 6.0
- **Platform**: macOS 15+, iOS 17+

---

## Common Issues

### "Cannot find [Type] in scope" in Xcode build

**Cause**: New Swift files not added to Xcode project

**Solution**: Open the `.xcodeproj` in Xcode and add the files to the target, or manually edit the `.pbxproj` file

### Build works with `swift build` but fails with `xcodebuild`

**Cause**: Xcode projects have separate build configuration from SPM

**Solution**: Ensure all dependencies are properly linked in Xcode project settings

### Distributed actor connection failures

**Cause**: Actor system not properly initialized or network issues

**Solution**:
- Check actor system host/port configuration in `configure.swift`
- Verify network connectivity between adapter and server
- Check logs for actor system bootstrap errors

### Database migration errors on startup

**Cause**: Migration not registered or schema conflicts

**Solution**:
- Ensure migration is added in `configure.swift`
- Check migration order (earlier migrations must succeed first)
- Manually inspect database schema vs expected schema

### SwiftLint warnings/errors

**Cause**: Code style violations

**Solution**: Run `swiftlint --fix` to auto-correct most issues

---

## Quick Reference

### Important Files for AI Assistants

**Core Domain:**
- `Sources/HAModels/HomeManagable.swift` - Main protocol for home interaction
- `Sources/HAModels/Automatable.swift` - Automation protocol
- `Sources/HAModels/EntityStorageItem.swift` - Entity state model
- `Sources/HAModels/EntityId.swift` - Entity identifier

**Application Layer:**
- `Sources/HAApplicationLayer/HomeManager.swift` - Central orchestrator
- `Sources/HAApplicationLayer/AutomationService.swift` - Event processing

**Server:**
- `Sources/Server/configure.swift` - Server configuration
- `Sources/Server/Controllers/OpenAPIController.swift` - API endpoints
- `Sources/Server/Models/EntityStorageDbItem.swift` - Database model

**API:**
- `openapi.yaml` - API specification

**Configuration:**
- `Package.swift` - Dependencies and targets
- `Dockerfile` - Server deployment
- `.swiftlint.yml` - Code style rules

### When to Update Which Files

| Task | Files to Update |
|------|----------------|
| Add new automation | `HAImplementations/`, `AnyAutomation.swift`, config YAML |
| Add entity field | Migration, `EntityStorageDbItem`, `openapi.yaml`, `EntityHistoryItem`, chart extensions |
| Add API endpoint | `openapi.yaml`, `OpenAPIController.swift` |
| Add device type | `HAImplementations/Devices/` |
| Modify HomeManager | `HAApplicationLayer/HomeManager.swift` |
| Add server job | `Server/Jobs/` |
| Modify iOS UI | `Controller/Features/`, TCA reducers |

### Common Commands

```bash
# Build everything
swift build

# Run tests
swift test

# Fix code style
swiftlint --fix

# Build iOS apps
cd Apps/FlowKitAdapter && xcodebuild -project "FlowKit Adapter.xcodeproj" -scheme "FlowKit Adapter" -sdk iphonesimulator build

# Start Docker environment
cd ../HomeAutomation-config-template && docker-compose up -d

# View logs
docker logs -f homeautomation-config-template-app-1

# Access database
docker exec -it homeautomation-config-template-db-1 mysql -u vapor_username -pvapor_password vapor_database
```

---

**Last Updated:** 2026-01-14
**Maintained By:** AI-assisted development with human oversight

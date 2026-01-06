# Claude Code Development Guide

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

- **Host**: `db` (inside Docker network only)
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

## Project Structure

- `Sources/` - Swift Package modules (HAModels, Adapter, Server, etc.)
- `Apps/FlowKitAdapter/` - HomeKit Adapter iOS app
- `Apps/FlowKitController/` - Home Automation Controller iOS app
- `Tests/` - Unit tests

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

## Database & API Schema Updates

### ⚠️ CRITICAL: When Adding New Entity Fields

When adding new sensor fields or entity properties, you MUST update **all three layers**:

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

## Common Issues

### "Cannot find [Type] in scope" in Xcode build

**Cause**: New Swift files not added to Xcode project

**Solution**: Open the `.xcodeproj` in Xcode and add the files to the target, or manually edit the `.pbxproj` file

### Build works with `swift build` but fails with `xcodebuild`

**Cause**: Xcode projects have separate build configuration from SPM

**Solution**: Ensure all dependencies are properly linked in Xcode project settings

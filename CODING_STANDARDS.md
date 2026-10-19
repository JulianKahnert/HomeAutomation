# Coding standards

What code in this repo has to look like. Read it before writing code; a reviewer checks a diff against it.

## Shared standards

Shared standards are generated from the Obsidian vault into `docs/coding-standards/` and never edited in the repo. Start at [docs/coding-standards/readme.md](docs/coding-standards/readme.md).

<!-- BEGIN shared file list: written by sync-coding-standards.py -->
- [`docs/coding-standards/general.md`](docs/coding-standards/general.md)
- [`docs/coding-standards/logging.md`](docs/coding-standards/logging.md)
- [`docs/coding-standards/macos-design.md`](docs/coding-standards/macos-design.md)
- [`docs/coding-standards/readme.md`](docs/coding-standards/readme.md)
- [`docs/coding-standards/swift-deprecations.md`](docs/coding-standards/swift-deprecations.md)
- [`docs/coding-standards/swift-testing.md`](docs/coding-standards/swift-testing.md)
- [`docs/coding-standards/swift.md`](docs/coding-standards/swift.md)
<!-- END shared file list -->

## This repo

### Security

- Authentication is **enabled by default** (secure by default)
- Server **crashes on startup** if `AUTH_TOKEN` is missing (fail-safe); release builds also require `DATABASE_PASSWORD`
- All endpoints on port 8080 require authentication, including the adapter WebSocket (`/adapter/v1`)
- Tokens are compared in constant time (`TokenAuthenticationMiddleware.constantTimeEquals`) — keep it that way
- `limit` query parameters are clamped server-side to the bounds declared in `openapi.yaml` (`OpenAPIController.clampedLimit`); the generator does not enforce them
- The adapter WebSocket rejects any `call`/`reply` frame that arrives before the peer's `hello` handshake frame
- `HealthCheck` automations only accept public `https` URLs (`HealthCheck.validate`) so `POST /config` cannot be used to reach internal services
- Set `DATABASE_TLS_VERIFY=true` when the MySQL connection leaves the private container network (see `docs/setup-server.md` for all environment variables)
- The adapter stores the server token in the keychain (`AdapterCredentialStore`), never in `UserDefaults`; enable **Use TLS (wss://)** in the adapter settings when it connects over an untrusted network
- Never commit secrets: `docker-compose.yml` must reference `${AUTH_TOKEN}` etc. from a git-ignored `.env`

### Before committing

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

### Git workflow

This project follows the **Git-Flow** branching model:

#### Branch Structure

- **`main`** - Production-ready releases only
  - Receives git tags for version releases
  - Never commit directly to this branch

- **`develop`** - Integration branch for features
  - Never work directly on this branch
  - All feature branches merge here via pull requests

#### Feature Development

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

#### Quick Reference

```bash
# Start new feature
git checkout develop && git pull && git checkout -b feature/123-my-feature

# Keep feature branch updated
git checkout develop && git pull && git checkout feature/123-my-feature && git merge develop

# Create PR (always target develop)
gh pr create --base develop --head feature/123-my-feature
```

### Database and API schema updates

When adding new sensor fields or entity properties, you MUST update **all three layers**:

##### 1. Database Migration (REQUIRED)
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

##### 2. Update Database Model
File: `Sources/Server/Models/EntityStorageDbItem.swift`

- Add `@Field` property to the model
- Update `map()` method to convert FROM `EntityStorageItem`
- Update `mapDbItem()` function to convert TO `EntityStorageItem`

##### 3. Update OpenAPI Schema (REQUIRED)
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

##### 4. Update API Response Model
File: `Sources/HAModels/EntityHistoryItem.swift`

- Add the new field as an optional property
- Update the `Codable` mapping if needed

##### 5. Update Chart Display Logic (Optional)
File: `Sources/Controller/Extensions/EntityHistoryItem+Chart.swift`

Add your field to `primaryValue` getter with appropriate priority:
```swift
var primaryValue: Double? {
    if let newField { return newField }  // Add here
    if let temperatureInC { return temperatureInC }
    // ... rest of priority list
}
```

##### 6. Update Server Controller
File: `Sources/Server/Controllers/OpenAPIController.swift`

In `getEntityHistory()`, ensure the field is mapped from `EntityStorageItem` to the OpenAPI response.

**When to update each:**
- **EntityStorageItem**: When HomeKit adapter reads new characteristics
- **EntityStorageDbItem**: ALWAYS when adding fields that need persistence
- **EntityHistoryItem**: ALWAYS when fields should appear in history charts

#### Migration Checklist

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

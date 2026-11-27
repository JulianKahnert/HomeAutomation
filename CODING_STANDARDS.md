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
   cd Apps/FlowKitController && xcodebuild -project "FlowKit Controller.xcodeproj" -scheme "FlowKit Controller" -destination 'generic/platform=iOS Simulator' -configuration Debug -skipPackagePluginValidation -skipMacroValidation build
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

The database has one initial schema (`Sources/Server/Migrations/01_InitialSchema.swift`, documented in `docs/database-schema.md`). A state is a value of a **value kind**, stored generically in `entityChanges` (`EntityChangeDbItem`: a number or a text per change) under its entity (`EntityDbItem`). A new kind of value therefore needs no migration, no column and no new field on the transport models.

**A new value kind costs three things:**

1. A `CharacteristicsType` case (`Sources/HAModels/Entities/CharacteristicsType.swift`).
2. Its `ValueDescriptor` in `ValueDescriptor.descriptor(for:)` (`Sources/HAModels/Entities/ValueDescriptor.swift`): the shape of the value, unit, display, constraint, whether the app may set it, and its storage rule (dead band, raw retention, hourly rollup, valid range). The switch is exhaustive, so a case without a descriptor does not compile.
3. The adapter mapping from the HomeKit characteristic (`Sources/Adapter/HomeKitCharacteristic.swift`, `Sources/Adapter/Extensions/HMCharacteristic.swift`), when the value comes from HomeKit. A server-owned value (placeId `server`, written with `HomeManagable.report`) needs no adapter mapping.

**Not needed for a new kind:** a migration, an `EntityDbItem` change, a change of `openapi.yaml`, of `EntityHistoryItem` or of the wire format. History items, the wire format and the charts carry whatever the descriptor says.

**A schema change** (a new column or table, which a new kind does not need) edits `01_InitialSchema.swift` for a new database. An existing database gets a separate migration script by hand, as for the move from the old schema (`docs/database-schema.md`); the migration list stays one entry.

#### Checklist

- [ ] New `CharacteristicsType` case with its `ValueDescriptor`
- [ ] Adapter mapping, when the value comes from HomeKit
- [ ] A test that the kind survives the wire and the history (`ValueKindExtensibilityTests` covers every case of `CharacteristicsType`)
- [ ] Tested with `swift build` and both app builds

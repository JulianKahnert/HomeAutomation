# ControllerFeatures

TCA-based architecture for the FlowKit Controller iOS app.

## Overview

This module implements The Composable Architecture (TCA) for the FlowKit Controller app, providing a unidirectional data flow architecture with testable business logic.

## Architecture

### App Feature
**AppFeature** (`App/AppFeature.swift`) - Root coordinator
- Manages tab navigation
- Coordinates Live Activities and push notifications
- Handles background tasks and window state synchronization

### Tab Features

1. **AutomationsFeature** (`Features/AutomationsFeature.swift`)
   - List and manage home automations
   - Activate, deactivate, and stop automations
   - Auto-refresh after operations

2. **ActionsFeature** (`Features/ActionsFeature.swift`)
   - View action log
   - Clear action history
   - Configurable action limit

3. **SettingsFeature** (`Features/SettingsFeature.swift`)
   - Server URL configuration
   - Live Activities toggle
   - Push notification management
   - Window states monitoring

### Dependencies

Custom dependencies wrap platform and network APIs:

- **FlowKitClientDependency** - OpenAPI client wrapper
- **LiveActivityDependency** - ActivityKit wrapper (iOS only)
- **PushNotificationDependency** - Push notification management

### Shared State

**SharedKeys** (`Shared/SharedKeys.swift`) - Persistent and in-memory state
- AppStorage-backed: `serverURL`, `liveActivitiesEnabled`
- In-memory: `automations`, `actions`, `windowContentState`

## Usage

### Basic Setup

```swift
import ControllerFeatures
import ComposableArchitecture

let store = Store(initialState: AppFeature.State()) {
    AppFeature()
}
```

### SwiftUI Integration

```swift
struct ContentView: View {
    let store: StoreOf<AppFeature>

    var body: some View {
        TabView(
            selection: viewStore.binding(
                get: \.selectedTab,
                send: { .selectedTabChanged($0) }
            )
        ) {
            AutomationsView(
                store: store.scope(
                    state: \.automations,
                    action: \.automations
                )
            )
            .tabItem { Label("Automations", systemImage: "lamp.floor") }
            .tag(AppFeature.Tab.automations)

            // Actions and Settings tabs...
        }
        .onAppear {
            store.send(.onAppear)
        }
    }
}
```

## Testing

Dependencies use `testValue` and `previewValue` for easy testing:

```swift
let store = TestStore(initialState: AutomationsFeature.State()) {
    AutomationsFeature()
} withDependencies: {
    $0.flowKitClient.getAutomations = {
        [Automation(name: "Test", isActive: true, isRunning: false)]
    }
}

await store.send(.onAppear)
await store.receive(\.refresh)
```

## Live Activities Integration

The app automatically:
1. Monitors window states from the server
2. Starts/updates Live Activities when windows are open
3. Registers push tokens for remote updates
4. Stops activities when disabled in settings

## Dependencies

- [swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture) - TCA framework
- [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) - Dependency injection
- [swift-sharing](https://github.com/pointfreeco/swift-sharing) - Shared state management

## Migration from Legacy Architecture

This module follows the PDF-Archiver pattern:
- Single target for all controller features
- TCA for state management and business logic
- Custom dependencies for testability
- Shared state for persistence

Legacy app code in `Apps/FlowKitController` will be gradually migrated to use these TCA features.

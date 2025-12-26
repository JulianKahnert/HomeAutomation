//
//  ServerClientDependency.swift
//  ControllerFeatures
//
//  Dependency wrapper for Server OpenAPI client
//

import Dependencies
import DependenciesMacros
import Foundation
import HAModels
import ServerClient
import Sharing

// MARK: - ServerClient Dependency

@DependencyClient
struct ServerClientDependency: Sendable {
    /// Get all automations from the server
    var getAutomations: @Sendable () async throws -> [AutomationInfo]

    /// Activate an automation by name
    var activate: @Sendable (_ name: String) async throws -> Void

    /// Deactivate an automation by name
    var deactivate: @Sendable (_ name: String) async throws -> Void

    /// Stop an automation by name
    var stop: @Sendable (_ name: String) async throws -> Void

    /// Get action log items
    var getActions: @Sendable (_ limit: Int?) async throws -> [ActionLogItem]

    /// Clear all action log items
    var clearActions: @Sendable () async throws -> Void

    /// Get window states for Live Activities
    var getWindowStates: @Sendable () async throws -> [WindowContentState.WindowState]

    /// Register device for push notifications
    var registerDevice: @Sendable (_ token: PushToken) async throws -> Void

    /// Get all entity IDs that have historical data
    var getEntityIdsWithHistory: @Sendable () async throws -> [EntityInfo]

    /// Get entity history with optional time range and pagination
    var getEntityHistory: @Sendable (
        _ entityId: EntityId,
        _ startDate: Date?,
        _ endDate: Date?,
        _ cursor: Date?,
        _ limit: Int
    ) async throws -> EntityHistoryResponse
}

// MARK: - Dependency Key Implementation

extension ServerClientDependency: TestDependencyKey {
    static let testValue = Self(
        getAutomations: { [] },
        activate: { _ in },
        deactivate: { _ in },
        stop: { _ in },
        getActions: { _ in [] },
        clearActions: { },
        getWindowStates: { [] },
        registerDevice: { _ in },
        getEntityIdsWithHistory: { [] },
        getEntityHistory: { _, _, _, _, _ in EntityHistoryResponse(items: [], nextCursor: nil) }
    )

    static let previewValue = Self(
        getAutomations: {
            [
                AutomationInfo(name: "Morning Routine", isActive: true, isRunning: true),
                AutomationInfo(name: "Evening Lights", isActive: true, isRunning: false),
                AutomationInfo(name: "Vacation Mode", isActive: false, isRunning: false)
            ]
        },
        activate: { _ in },
        deactivate: { _ in },
        stop: { _ in },
        getActions: { _ in
            [
                ActionLogItem(
                    id: UUID(),
                    timestamp: Date(),
                    entityId: EntityId(placeId: "living-room", name: "Main Light", characteristicsName: "switcher", characteristic: .switcher),
                    actionName: "Turn On",
                    detailDescription: "Turned on living room light",
                    hasCacheHit: false
                )
            ]
        },
        clearActions: { },
        getWindowStates: {
            [
                WindowContentState.WindowState(
                    name: "Living Room Window",
                    opened: Date().addingTimeInterval(-3600),
                    maxOpenDuration: 7200
                )
            ]
        },
        registerDevice: { _ in },
        getEntityIdsWithHistory: {
            [
                EntityInfo(
                    entityId: EntityId(placeId: "living-room", name: "Motion Sensor", characteristicsName: "motionSensor", characteristic: .motionSensor)
                ),
                EntityInfo(
                    entityId: EntityId(placeId: "bedroom", name: "Light Sensor", characteristicsName: "lightSensor", characteristic: .lightSensor)
                )
            ]
        },
        getEntityHistory: { entityId, _, _, _, _ in
            // Generate realistic data based on entity type
            let items: [EntityHistoryItem]

            if entityId.characteristicType == .lightSensor {
                // Realistic lux values for a 24-hour period (daytime cycle)
                let now = Date()
                items = [
                    // Night (0:00 - 5:00) - very low light
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 0 * 3600), illuminanceInLux: 0.5),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 1 * 3600), illuminanceInLux: 0.3),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 2 * 3600), illuminanceInLux: 0.2),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 3 * 3600), illuminanceInLux: 0.1),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 4 * 3600), illuminanceInLux: 0.2),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 5 * 3600), illuminanceInLux: 1.0),

                    // Sunrise (6:00 - 8:00) - rapidly increasing
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 6 * 3600), illuminanceInLux: 50),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 7 * 3600), illuminanceInLux: 250),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 8 * 3600), illuminanceInLux: 800),

                    // Morning (9:00 - 11:00) - bright increasing
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 9 * 3600), illuminanceInLux: 2500),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 10 * 3600), illuminanceInLux: 5500),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 11 * 3600), illuminanceInLux: 8000),

                    // Midday (12:00 - 14:00) - peak brightness
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 12 * 3600), illuminanceInLux: 12000),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 13 * 3600), illuminanceInLux: 15000),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 14 * 3600), illuminanceInLux: 13500),

                    // Afternoon (15:00 - 17:00) - decreasing
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 15 * 3600), illuminanceInLux: 9000),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 16 * 3600), illuminanceInLux: 4500),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 17 * 3600), illuminanceInLux: 1800),

                    // Sunset (18:00 - 20:00) - rapidly decreasing
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 18 * 3600), illuminanceInLux: 450),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 19 * 3600), illuminanceInLux: 85),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 20 * 3600), illuminanceInLux: 12),

                    // Evening (21:00 - 23:00) - low light
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 21 * 3600), illuminanceInLux: 3.5),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 22 * 3600), illuminanceInLux: 1.2),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 23 * 3600), illuminanceInLux: 0.8)
                ]
            } else if entityId.characteristicType == .batterySensor {
                // Realistic battery percentage values (slowly decreasing)
                let now = Date()
                items = [
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 0 * 3600), stateOfCharge: 95),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 6 * 3600), stateOfCharge: 89),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 12 * 3600), stateOfCharge: 83),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 18 * 3600), stateOfCharge: 76),
                    EntityHistoryItem(timestamp: now.addingTimeInterval(-86400 + 24 * 3600), stateOfCharge: 71)
                ]
            } else {
                // Boolean sensor (motion, contact, etc.)
                items = [
                    EntityHistoryItem(timestamp: Date().addingTimeInterval(-3600), isDeviceOn: true),
                    EntityHistoryItem(timestamp: Date().addingTimeInterval(-7200), isDeviceOn: false)
                ]
            }

            return EntityHistoryResponse(items: items, nextCursor: nil)
        }
    )
}

extension ServerClientDependency: DependencyKey {

    static var client: ServerClient {
        @Shared(.serverURL) var serverURL
         return ServerClient(url: serverURL)
    }

    /// Live implementation will be provided when Xcode project is integrated
    /// with the OpenAPI generated client
    static let liveValue = Self(
        getAutomations: {
            try await client.getAutomations()
        },
        activate: { name in
            try await client.activate(automation: name)
        },
        deactivate: { name in
             try await client.deactivate(automation: name)
        },
        stop: { name in
             try await client.stop(automation: name)
        },
        getActions: { limit in
            try await client.getActions(limit: limit)
        },
        clearActions: {
            try await client.clearActions()
        },
        getWindowStates: {
            try await client.getWindowStates()
        },
        registerDevice: { token in
            try await client.register(token: token)
        },
        getEntityIdsWithHistory: {
            try await client.getEntityIdsWithHistory()
        },
        getEntityHistory: { entityId, startDate, endDate, cursor, limit in
            try await client.getEntityHistory(
                entityId: entityId,
                startDate: startDate,
                endDate: endDate,
                cursor: cursor,
                limit: limit
            )
        }
    )
}

// MARK: - DependencyValues Extension

extension DependencyValues {
    var serverClient: ServerClientDependency {
        get { self[ServerClientDependency.self] }
        set { self[ServerClientDependency.self] = newValue }
    }
}

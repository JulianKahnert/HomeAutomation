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

/// Push device token type
enum PushDeviceTokenType: String, Sendable, Codable {
    case apns
    case fcm
}

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
        registerDevice: { _ in }
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
        registerDevice: { _ in }
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

//
//  FlowKitClientDependency.swift
//  ControllerFeatures
//
//  Dependency wrapper for FlowKit OpenAPI client
//

import Dependencies
import DependenciesMacros
import Foundation
import HAModels

// MARK: - Type Aliases for OpenAPI Generated Types
// These will be properly imported once Xcode project integration is complete

/// Automation type from OpenAPI schema
/// Will be: typealias Automation = Components.Schemas.Automation
public struct Automation: Identifiable, Sendable, Codable, Equatable {
    public let name: String
    public let isActive: Bool
    public let isRunning: Bool

    public var id: String { name }

    public init(name: String, isActive: Bool, isRunning: Bool) {
        self.name = name
        self.isActive = isActive
        self.isRunning = isRunning
    }
}

/// Push device token type
public enum PushDeviceTokenType: String, Sendable, Codable {
    case apns
    case fcm
}

// MARK: - FlowKitClient Dependency

@DependencyClient
public struct FlowKitClientDependency: Sendable {
    /// Get all automations from the server
    public var getAutomations: @Sendable () async throws -> [Automation]

    /// Activate an automation by name
    public var activate: @Sendable (_ name: String) async throws -> Void

    /// Deactivate an automation by name
    public var deactivate: @Sendable (_ name: String) async throws -> Void

    /// Stop an automation by name
    public var stop: @Sendable (_ name: String) async throws -> Void

    /// Get action log items
    public var getActions: @Sendable (_ limit: Int?) async throws -> [ActionLogItem]

    /// Clear all action log items
    public var clearActions: @Sendable () async throws -> Void

    /// Get window states for Live Activities
    public var getWindowStates: @Sendable () async throws -> [WindowContentState.WindowState]

    /// Register device for push notifications
    public var registerDevice: @Sendable (
        _ deviceName: String,
        _ tokenString: String,
        _ tokenType: PushDeviceTokenType,
        _ activityType: String?
    ) async throws -> Void
}

// MARK: - Dependency Key Implementation

extension FlowKitClientDependency: TestDependencyKey {
    public static let testValue = Self(
        getAutomations: { [] },
        activate: { _ in },
        deactivate: { _ in },
        stop: { _ in },
        getActions: { _ in [] },
        clearActions: { },
        getWindowStates: { [] },
        registerDevice: { _, _, _, _ in }
    )

    public static let previewValue = Self(
        getAutomations: {
            [
                Automation(name: "Morning Routine", isActive: true, isRunning: true),
                Automation(name: "Evening Lights", isActive: true, isRunning: false),
                Automation(name: "Vacation Mode", isActive: false, isRunning: false)
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
        registerDevice: { _, _, _, _ in }
    )
}

extension FlowKitClientDependency: DependencyKey {
    /// Live implementation will be provided when Xcode project is integrated
    /// with the OpenAPI generated client
    public static let liveValue = Self(
        getAutomations: {
            // TODO: Wire up actual FlowKitClient when integrated with Xcode project
            // let client = FlowKitClient(url: serverURL)
            // return try await client.getAutomations()
            []
        },
        activate: { _ in
            // TODO: Wire up actual FlowKitClient
            // let client = FlowKitClient(url: serverURL)
            // try await client.activate(automation: name)
        },
        deactivate: { _ in
            // TODO: Wire up actual FlowKitClient
            // let client = FlowKitClient(url: serverURL)
            // try await client.deactivate(automation: name)
        },
        stop: { _ in
            // TODO: Wire up actual FlowKitClient
            // let client = FlowKitClient(url: serverURL)
            // try await client.stop(automation: name)
        },
        getActions: { _ in
            // TODO: Wire up actual FlowKitClient
            // let client = FlowKitClient(url: serverURL)
            // return try await client.getActions(limit: limit)
            []
        },
        clearActions: {
            // TODO: Wire up actual FlowKitClient
            // let client = FlowKitClient(url: serverURL)
            // try await client.clearActions()
        },
        getWindowStates: {
            // TODO: Wire up actual FlowKitClient
            // let client = FlowKitClient(url: serverURL)
            // return try await client.getWindowStates()
            []
        },
        registerDevice: { _, _, _, _ in
            // TODO: Wire up actual FlowKitClient
            // let client = FlowKitClient(url: serverURL)
            // try await client.register(...)
        }
    )
}

// MARK: - DependencyValues Extension

public extension DependencyValues {
    var flowKitClient: FlowKitClientDependency {
        get { self[FlowKitClientDependency.self] }
        set { self[FlowKitClientDependency.self] = newValue }
    }
}

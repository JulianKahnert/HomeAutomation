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

    /// `true` when the server reaches its adapter
    var isHealthy: @Sendable () async throws -> Bool

    /// Runs of one automation, newest first
    var getRuns: @Sendable (_ automation: String, _ startDate: Date?, _ endDate: Date?, _ limit: Int?) async throws -> [AutomationRun]

    /// Runs of all automations since a date, newest first
    var getRecentRuns: @Sendable (_ since: Date, _ limit: Int?) async throws -> [AutomationRun]

    /// Get action log items, optionally only those sent by one run
    var getActions: @Sendable (_ limit: Int?, _ runId: UUID?) async throws -> [ActionLogItem]

    /// Clear all action log items
    var clearActions: @Sendable () async throws -> Void

    /// Get the offenen Fenster as the server's Live Activity content state, in server order
    var getWindowContentState: @Sendable () async throws -> WindowContentState

    /// Register device for push notifications
    var registerDevice: @Sendable (_ token: PushToken) async throws -> Void

    /// Get entity history with optional time range and pagination
    var getEntityHistory: @Sendable (
        _ entityId: EntityId,
        _ startDate: Date?,
        _ endDate: Date?,
        _ cursor: Date?,
        _ limit: Int,
        _ includePrevious: Bool
    ) async throws -> EntityHistoryResponse

    /// History of every entity in a room, newest first per entity
    var getRoomHistory: @Sendable (_ placeId: String, _ startDate: Date?, _ endDate: Date?, _ includePrevious: Bool) async throws -> [EntityHistory]

    /// The overview of all heating rooms: actual, plan target and source per room
    var getHeatingOverview: @Sendable () async throws -> HeatingOverview

    /// The time grid of one heating room for a range
    var getHeatingRoom: @Sendable (_ placeId: String, _ range: HeatingRange) async throws -> HeatingRoomDetail

    /// The state of the fireplace switch
    var getFireplace: @Sendable () async throws -> FireplaceState

    /// Switches the fireplace on or off; answers the state it will have
    var setFireplace: @Sendable (_ isOn: Bool) async throws -> FireplaceState

    /// The server's location, used for sunrise and sunset
    var getLocation: @Sendable () async throws -> Location
}

// MARK: - Dependency Key Implementation

extension ServerClientDependency: TestDependencyKey {
    static let testValue = Self(
        getAutomations: { [] },
        activate: { _ in },
        deactivate: { _ in },
        stop: { _ in },
        isHealthy: { true },
        getRuns: { _, _, _, _ in [] },
        getRecentRuns: { _, _ in [] },
        getActions: { _, _ in [] },
        clearActions: { },
        getWindowContentState: { .empty },
        registerDevice: { _ in },
        getEntityHistory: { _, _, _, _, _, _ in EntityHistoryResponse(items: [], nextCursor: nil) },
        getRoomHistory: { _, _, _, _ in [] },
        getHeatingOverview: { HeatingOverview(rooms: []) },
        getHeatingRoom: { placeId, range in HeatingRoomDetail(placeId: placeId, name: placeId, range: range, istSource: .thermostats([]), radiators: [], samples: []) },
        getFireplace: { .off },
        setFireplace: { isOn in isOn ? FireplaceState(isOn: true, since: Date()) : .off },
        getLocation: { Location(latitude: 52.5, longitude: 13.4) }
    )

    static let previewValue = Self(
        getAutomations: {
            [
                AutomationInfo(name: "Hallway Night Light", isActive: true, isRunning: true, type: "MotionAtNight", lastRun: previewRuns[0]),
                AutomationInfo(name: "Evening Lights", isActive: true, isRunning: false, type: "Turn", lastRun: previewRuns[1]),
                AutomationInfo(name: "Vacation Mode", isActive: false, isRunning: false, type: "TriggerScene")
            ]
        },
        activate: { _ in },
        deactivate: { _ in },
        stop: { _ in },
        isHealthy: { true },
        getRuns: { name, _, _, _ in previewRuns.filter { $0.automationName == name } },
        getRecentRuns: { _, _ in previewRuns },
        getActions: { _, _ in
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
        getWindowContentState: {
            let opened = Date().addingTimeInterval(-3600)
            return WindowContentState(sortedWindows: [
                WindowContentState.Window(
                    id: WindowContentState.Window.id(room: "Living Room", name: "Window"),
                    name: "Window",
                    room: "Living Room",
                    opened: opened,
                    closeBy: opened.addingTimeInterval(7200),
                    isOverdue: false
                )
            ])
        },
        registerDevice: { _ in },
        getEntityHistory: { entityId, _, _, _, _, _ in
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
        },
        getRoomHistory: { _, _, _, _ in [] },
        getHeatingOverview: { HeatingOverview(rooms: HeatingPreviewData.overviewRooms) },
        getHeatingRoom: { placeId, range in
            HeatingPreviewData.rooms.first { $0.id == placeId }?.detail(range) ?? HeatingPreviewData.rooms[0].detail(range)
        },
        getFireplace: { .off },
        setFireplace: { isOn in isOn ? FireplaceState(isOn: true, since: Date()) : .off },
        getLocation: { Location(latitude: 52.5, longitude: 13.4) }
    )

    private static let previewRuns = [
        AutomationRun(
            automationName: "Hallway Night Light",
            startedAt: Date().addingTimeInterval(-120),
            trigger: AutomationTrigger(kind: .entityChange, entityId: nil, summary: "Motion · Eve Motion (Hallway)"),
            outcome: .running
        ),
        AutomationRun(
            automationName: "Evening Lights",
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date().addingTimeInterval(-3590),
            trigger: AutomationTrigger(kind: .sunset, entityId: nil, summary: "Sunset"),
            outcome: .failed,
            errorDescription: "Ceiling Light (Living Room) not reachable"
        )
    ]
}

extension ServerClientDependency: DependencyKey {

    static var client: ServerClient {
        @Shared(.serverURL) var serverURL
        @Shared(.authToken) var authToken
        return ServerClient(url: serverURL, authToken: authToken)
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
        isHealthy: {
            try await client.isHealthy()
        },
        getRuns: { name, startDate, endDate, limit in
            try await client.getRuns(automation: name, startDate: startDate, endDate: endDate, limit: limit)
        },
        getRecentRuns: { since, limit in
            try await client.getRecentRuns(since: since, limit: limit)
        },
        getActions: { limit, runId in
            try await client.getActions(limit: limit, runId: runId)
        },
        clearActions: {
            try await client.clearActions()
        },
        getWindowContentState: {
            try await client.getWindowContentState()
        },
        registerDevice: { token in
            try await client.register(token: token)
        },
        getEntityHistory: { entityId, startDate, endDate, cursor, limit, includePrevious in
            try await client.getEntityHistory(
                entityId: entityId,
                startDate: startDate,
                endDate: endDate,
                cursor: cursor,
                limit: limit,
                includePrevious: includePrevious
            )
        },
        getRoomHistory: { placeId, startDate, endDate, includePrevious in
            try await client.getRoomHistory(placeId: placeId, startDate: startDate, endDate: endDate, includePrevious: includePrevious)
        },
        getHeatingOverview: {
            try await client.getHeatingOverview()
        },
        getHeatingRoom: { placeId, range in
            try await client.getHeatingRoom(placeId: placeId, range: range)
        },
        getFireplace: {
            try await client.getFireplace()
        },
        setFireplace: { isOn in
            try await client.setFireplace(isOn: isOn)
        },
        getLocation: {
            try await client.getLocation()
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

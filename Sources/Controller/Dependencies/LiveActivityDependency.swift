//
//  LiveActivityDependency.swift
//  ControllerFeatures
//
//  Dependency wrapper for Live Activities management
//

#if os(iOS)
import ActivityKit
import Dependencies
import DependenciesMacros
import Foundation
import HAModels
import Shared
import UIKit

// MARK: - LiveActivity Dependency

@DependencyClient
struct LiveActivityDependency: Sendable {
    /// Start a new Live Activity with initial window states
    var startActivity: @Sendable (_ windowStates: [WindowContentState.WindowState]) async throws -> Void

    /// Update the current Live Activity with new window states
    var updateActivity: @Sendable (_ windowStates: [WindowContentState.WindowState]) async -> Void

    /// Stop the current Live Activity
    var stopActivity: @Sendable () async -> Void

    /// Stream of push token updates for the current activity
    var pushTokenUpdates: @Sendable () async -> AsyncStream<PushToken> = { .finished }

    /// Stream of push-to-start tokens
    var pushToStartTokenUpdates: @Sendable () async -> AsyncStream<PushToken> = { .finished }
    
    /// Check if Live Activities are currently running
    var hasActiveActivities: @Sendable () async -> Bool = { false }
}

// MARK: - Dependency Key Implementation

extension LiveActivityDependency: TestDependencyKey {
    static let testValue = Self(
        startActivity: { _ in },
        updateActivity: { _ in },
        stopActivity: { },
        pushTokenUpdates: { .finished },
        pushToStartTokenUpdates: { .finished },
        hasActiveActivities: { false }
    )

    static let previewValue = Self(
        startActivity: { _ in },
        updateActivity: { _ in },
        stopActivity: { },
        pushTokenUpdates: {
            AsyncStream { continuation in
                // Simulate a push token
                let mockToken = PushToken(deviceName: "preview", tokenString: "1234", type: .pushNotification)
                continuation.yield(mockToken)
                continuation.finish()
            }
        },
        pushToStartTokenUpdates: { .finished },
        hasActiveActivities: { true }
    )
}

extension LiveActivityDependency: DependencyKey {
    static let liveValue: Self = {
        return Self(
            startActivity: { windowStates in
                let initialState = WindowContentState(windowStates: windowStates)
                let activity = try Activity<WindowAttributes>.request(
                    attributes: WindowAttributes(),
                    content: .init(state: initialState, staleDate: nil),
                    pushType: .token
                )
                print("Live Activity started: \(activity.id)")
            },
            updateActivity: { windowStates in
                guard let activity = Activity<WindowAttributes>.activities.last else { return }
                let newState = WindowContentState(windowStates: windowStates)
                await activity.update(.init(state: newState, staleDate: nil))
            },
            stopActivity: {
                for activity in Activity<WindowAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            },
            pushTokenUpdates: {
                AsyncStream { continuation in
                    let task = Task {
                        guard let activity = Activity<WindowAttributes>.activities.last else {
                            continuation.finish()
                            return
                        }
                        for await tokenData in activity.pushTokenUpdates {
                            let token = await PushToken(deviceName: UIDevice.current.name,
                                                        tokenString: tokenData.hexadecimalString,
                                                        type: .liveActivityUpdate(activityName: String(describing: activity.self)))
                            continuation.yield(token)
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            pushToStartTokenUpdates: {
                AsyncStream { continuation in
                    let task = Task {
                        for await pushTokenData in Activity<WindowAttributes>.pushToStartTokenUpdates {
                            let token = await PushToken(deviceName: UIDevice.current.name,
                                                        tokenString: pushTokenData.hexadecimalString,
                                                        type: .liveActivityStart)
                            continuation.yield(token)
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            hasActiveActivities: {
                !Activity<WindowAttributes>.activities.isEmpty
            }
        )
    }()
}

// MARK: - DependencyValues Extension

extension DependencyValues {
    var liveActivity: LiveActivityDependency {
        get { self[LiveActivityDependency.self] }
        set { self[LiveActivityDependency.self] = newValue }
    }
}
#endif

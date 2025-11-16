//
//  LiveActivityDependency.swift
//  ControllerFeatures
//
//  Dependency wrapper for Live Activities management
//

#if canImport(ActivityKit)
import ActivityKit
#endif
import Dependencies
import DependenciesMacros
import Foundation
import HAModels

// MARK: - LiveActivity Dependency

@DependencyClient
public struct LiveActivityDependency: Sendable {
    /// Start a new Live Activity with initial window states
    public var startActivity: @Sendable (_ windowStates: [WindowContentState.WindowState]) async throws -> Void

    /// Update the current Live Activity with new window states
    public var updateActivity: @Sendable (_ windowStates: [WindowContentState.WindowState]) async -> Void

    /// Stop the current Live Activity
    public var stopActivity: @Sendable () async -> Void

    /// Stream of activity authorization updates (iOS only)
    /// On non-iOS platforms, this will return an empty stream
    public var activityUpdates: @Sendable () async -> AsyncStream<String> = { .finished }

    /// Stream of push token updates for the current activity
    public var pushTokenUpdates: @Sendable () async -> AsyncStream<Data> = { .finished }

    /// Stream of content updates from the current activity
    public var contentUpdates: @Sendable () async -> AsyncStream<WindowContentState> = { .finished }

    /// Stream of push-to-start tokens
    public var pushToStartTokenUpdates: @Sendable () async -> AsyncStream<Data> = { .finished }

    /// Get the current activity state (if any)
    public var currentActivityState: @Sendable () async -> WindowContentState? = { nil }

    /// Check if Live Activities are currently running
    public var hasActiveActivities: @Sendable () async -> Bool = { false }
}

// MARK: - Dependency Key Implementation

extension LiveActivityDependency: TestDependencyKey {
    public static let testValue = Self(
        startActivity: { _ in },
        updateActivity: { _ in },
        stopActivity: { },
        activityUpdates: { .finished },
        pushTokenUpdates: { .finished },
        contentUpdates: { .finished },
        pushToStartTokenUpdates: { .finished },
        currentActivityState: { nil },
        hasActiveActivities: { false }
    )

    public static let previewValue = Self(
        startActivity: { _ in },
        updateActivity: { _ in },
        stopActivity: { },
        activityUpdates: {
            AsyncStream { continuation in
                continuation.yield("preview")
                continuation.finish()
            }
        },
        pushTokenUpdates: {
            AsyncStream { continuation in
                // Simulate a push token
                let mockToken = Data([0x01, 0x02, 0x03, 0x04])
                continuation.yield(mockToken)
                continuation.finish()
            }
        },
        contentUpdates: {
            AsyncStream { continuation in
                let mockState = WindowContentState(windowStates: [
                    .init(name: "Preview Window", opened: Date(), maxOpenDuration: 3600)
                ])
                continuation.yield(mockState)
                continuation.finish()
            }
        },
        pushToStartTokenUpdates: { .finished },
        currentActivityState: {
            WindowContentState(windowStates: [
                .init(name: "Preview Window", opened: Date(), maxOpenDuration: 3600)
            ])
        },
        hasActiveActivities: { true }
    )
}

extension LiveActivityDependency: DependencyKey {
    public static let liveValue: Self = {
        #if canImport(ActivityKit) && os(iOS)
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
            activityUpdates: {
                AsyncStream { continuation in
                    #if os(iOS)
                    let task = Task {
                        for await info in ActivityAuthorizationInfo.authorizationUpdates {
                            continuation.yield(String(describing: info))
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                    #else
                    continuation.finish()
                    #endif
                }
            },
            pushTokenUpdates: {
                AsyncStream { continuation in
                    let task = Task {
                        guard let activity = Activity<WindowAttributes>.activities.last else {
                            continuation.finish()
                            return
                        }
                        for await token in activity.pushTokenUpdates {
                            continuation.yield(token)
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            contentUpdates: {
                AsyncStream { continuation in
                    let task = Task {
                        guard let activity = Activity<WindowAttributes>.activities.last else {
                            continuation.finish()
                            return
                        }
                        for await content in activity.contentUpdates {
                            continuation.yield(content.state)
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            pushToStartTokenUpdates: {
                AsyncStream { continuation in
                    let task = Task {
                        for await pushToken in Activity<WindowAttributes>.pushToStartTokenUpdates {
                            continuation.yield(pushToken)
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            currentActivityState: {
                Activity<WindowAttributes>.activities.last?.content.state
            },
            hasActiveActivities: {
                !Activity<WindowAttributes>.activities.isEmpty
            }
        )
        #else
        // macOS or non-ActivityKit platform
        return Self(
            startActivity: { _ in
                print("Live Activities not available on this platform")
            },
            updateActivity: { _ in },
            stopActivity: { },
            activityUpdates: { .finished },
            pushTokenUpdates: { .finished },
            contentUpdates: { .finished },
            pushToStartTokenUpdates: { .finished },
            currentActivityState: { nil },
            hasActiveActivities: { false }
        )
        #endif
    }()
}

// MARK: - DependencyValues Extension

public extension DependencyValues {
    var liveActivity: LiveActivityDependency {
        get { self[LiveActivityDependency.self] }
        set { self[LiveActivityDependency.self] = newValue }
    }
}

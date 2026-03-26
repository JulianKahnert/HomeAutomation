//
//  LiveActivityDependency.swift
//  ControllerFeatures
//
//  Dependency wrapper for Live Activities management
//

import Dependencies
import DependenciesMacros
import Foundation
import HAModels
import Logging
import Shared

// MARK: - LiveActivity Dependency

@DependencyClient
struct LiveActivityDependency: Sendable {
    /// Start a new Live Activity with initial window states.
    ///
    /// This intentionally does **not** end existing activities before creating a new one.
    /// Duplicate cleanup is handled by ``updateActivity`` which keeps only the most recent
    /// activity and ends all others. This separation ensures that `startActivity` remains
    /// a simple, single-responsibility operation while `updateActivity` serves as the
    /// centralized deduplication point — which is always called when window states change.
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

#if os(iOS)
@preconcurrency import ActivityKit
import UIKit

private let logger = Logger(label: "LiveActivityDependency")

extension LiveActivityDependency: DependencyKey {
    static let liveValue: Self = {
        return Self(
            startActivity: { windowStates in
                logger.info("Starting new Live Activity with \(windowStates.count) window(s)")
                let initialState = WindowContentState(windowStates: windowStates)
                let activity = try Activity<WindowAttributes>.request(
                    attributes: WindowAttributes(),
                    content: .init(state: initialState, staleDate: nil),
                    pushType: .token
                )
                logger.info("Live Activity started: id=\(activity.id)")
            },
            updateActivity: { windowStates in
                var activities = Activity<WindowAttributes>.activities
                let lastActivity = activities.popLast()

                guard let lastActivity else {
                    assertionFailure("Did not find any activity")
                    logger.error("updateActivity called but no active activities found")
                    return
                }

                logger.info("Updating Live Activity: id=\(lastActivity.id), windows=\(windowStates.count), ending \(activities.count) duplicate(s)")
                let newState = WindowContentState(windowStates: windowStates)
                await lastActivity.update(.init(state: newState, staleDate: nil))

                for activity in activities {
                    logger.info("Ending duplicate Live Activity: id=\(activity.id)")
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            },
            stopActivity: {
                let activities = Activity<WindowAttributes>.activities
                logger.info("Stopping \(activities.count) Live Activity(s)")
                for activity in activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            },
            pushTokenUpdates: {
                AsyncStream { continuation in
                    let task = Task {
                        // Use withDiscardingTaskGroup so each activity's token stream is
                        // observed concurrently. The previous nested for-await blocked the
                        // outer loop, preventing token observation for newly created activities.
                        await withDiscardingTaskGroup { group in
                            for await activity in Activity<WindowAttributes>.activityUpdates {
                                logger.info("activityUpdates emitted activity: id=\(activity.id)")
                                group.addTask {
                                    for await tokenData in activity.pushTokenUpdates {
                                        let tokenString = tokenData.hexadecimalString
                                        logger.info("pushTokenUpdates emitted for activity \(activity.id): token=\(String(tokenString.prefix(8)))...")
                                        let token = await PushToken(
                                            deviceName: UIDevice.current.name,
                                            tokenString: tokenString,
                                            type: .liveActivityUpdate(activityName: WindowContentState.activityTypeName)
                                        )
                                        continuation.yield(token)
                                    }
                                }
                            }
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            pushToStartTokenUpdates: {
                AsyncStream { continuation in
                    let task = Task {
                        for await pushTokenData in Activity<WindowAttributes>.pushToStartTokenUpdates {
                            let tokenString = pushTokenData.hexadecimalString
                            logger.info("pushToStartTokenUpdates emitted: token=\(String(tokenString.prefix(8)))...")
                            let token = await PushToken(deviceName: UIDevice.current.name,
                                                        tokenString: tokenString,
                                                        type: .liveActivityStart)
                            continuation.yield(token)
                        }
                    }
                    continuation.onTermination = { _ in task.cancel() }
                }
            },
            hasActiveActivities: {
                let count = Activity<WindowAttributes>.activities.count
                logger.debug("hasActiveActivities: \(count) active")
                return count > 0
            }
        )
    }()
}
#else
extension LiveActivityDependency: DependencyKey {
    static let liveValue = Self.testValue
}
#endif

// MARK: - DependencyValues Extension

extension DependencyValues {
    var liveActivity: LiveActivityDependency {
        get { self[LiveActivityDependency.self] }
        set { self[LiveActivityDependency.self] = newValue }
    }
}

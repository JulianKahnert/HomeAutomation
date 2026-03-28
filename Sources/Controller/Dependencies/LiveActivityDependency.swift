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

    /// Observe push token updates for all activities.
    /// Runs in the caller's structured concurrency context — cancellation propagates automatically.
    var pushTokenUpdates: @Sendable (_ onToken: @Sendable (PushToken) async -> Void) async -> Void = { _ in }

    /// Observe push-to-start token updates.
    /// Runs in the caller's structured concurrency context — cancellation propagates automatically.
    var pushToStartTokenUpdates: @Sendable (_ onToken: @Sendable (PushToken) async -> Void) async -> Void = { _ in }

    /// Check if Live Activities are currently running
    var hasActiveActivities: @Sendable () async -> Bool = { false }
}

// MARK: - Dependency Key Implementation

extension LiveActivityDependency: TestDependencyKey {
    static let testValue = Self(
        startActivity: { _ in },
        updateActivity: { _ in },
        stopActivity: { },
        pushTokenUpdates: { _ in },
        pushToStartTokenUpdates: { _ in },
        hasActiveActivities: { false }
    )

    static let previewValue = Self(
        startActivity: { _ in },
        updateActivity: { _ in },
        stopActivity: { },
        pushTokenUpdates: { onToken in
            let mockToken = PushToken(deviceName: "preview", tokenString: "1234", type: .pushNotification)
            await onToken(mockToken)
        },
        pushToStartTokenUpdates: { _ in },
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
            pushTokenUpdates: { onToken in
                // Runs directly in the caller's structured concurrency context.
                // cancelInFlight: true on the TCA effect cancels this entire tree.
                await withDiscardingTaskGroup { group in
                    for await activity in Activity<WindowAttributes>.activityUpdates {
                        let totalActive = Activity<WindowAttributes>.activities.count
                        logger.info("activityUpdates emitted activity: id=\(activity.id), totalActive=\(totalActive)")

                        if totalActive > 1 {
                            let allActivities = Activity<WindowAttributes>.activities
                            for oldActivity in allActivities where oldActivity.id != activity.id {
                                logger.info("Ending stale Live Activity: id=\(oldActivity.id)")
                                await oldActivity.end(nil, dismissalPolicy: .immediate)
                            }
                        }

                        group.addTask {
                            for await tokenData in activity.pushTokenUpdates {
                                let tokenString = tokenData.hexadecimalString
                                logger.info("pushTokenUpdates emitted for activity \(activity.id): token=\(String(tokenString.prefix(8)))...")
                                let token = await PushToken(
                                    deviceName: UIDevice.current.name,
                                    tokenString: tokenString,
                                    type: .liveActivityUpdate(activityName: WindowContentState.activityTypeName)
                                )
                                await onToken(token)
                            }
                        }
                    }
                }
            },
            pushToStartTokenUpdates: { onToken in
                // Runs directly in the caller's structured concurrency context.
                for await pushTokenData in Activity<WindowAttributes>.pushToStartTokenUpdates {
                    let tokenString = pushTokenData.hexadecimalString
                    logger.info("pushToStartTokenUpdates emitted: token=\(String(tokenString.prefix(8)))...")
                    let token = await PushToken(deviceName: UIDevice.current.name,
                                                tokenString: tokenString,
                                                type: .liveActivityStart)
                    await onToken(token)
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

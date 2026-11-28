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
    /// Start a new Live Activity with the initial content state.
    ///
    /// This intentionally does **not** end existing activities before creating a new one.
    /// Duplicate cleanup is handled by ``updateActivity`` which keeps only the most recent
    /// activity and ends all others. This separation ensures that `startActivity` remains
    /// a simple, single-responsibility operation while `updateActivity` serves as the
    /// centralized deduplication point — which is always called when window states change.
    var startActivity: @Sendable (_ contentState: WindowContentState) async throws -> Void

    /// Update the current Live Activity with a new content state
    var updateActivity: @Sendable (_ contentState: WindowContentState) async -> Void

    /// Stop the current Live Activity
    var stopActivity: @Sendable () async -> Void

    /// Observe push token updates for all activities.
    /// Runs in the caller's structured concurrency context — cancellation propagates automatically.
    var pushTokenUpdates: @Sendable (_ onToken: @escaping @Sendable (PushToken) async -> Void) async -> Void

    /// Observe push-to-start token updates.
    /// Runs in the caller's structured concurrency context — cancellation propagates automatically.
    var pushToStartTokenUpdates: @Sendable (_ onToken: @escaping @Sendable (PushToken) async -> Void) async -> Void

    /// Check if Live Activities are currently running
    var hasActiveActivities: @Sendable () async -> Bool = { false }

    /// Ends the fireplace question on this device at once; the server ends it on the other devices.
    var endFireplaceQuestion: @Sendable () async -> Void
}

// MARK: - Dependency Key Implementation

extension LiveActivityDependency: TestDependencyKey {
    /// Every call that a test did not override reports an issue.
    static let testValue = Self()

    static let previewValue = Self(
        startActivity: { _ in },
        updateActivity: { _ in },
        stopActivity: { },
        pushTokenUpdates: { onToken in
            let mockToken = PushToken(deviceName: "preview", tokenString: "1234", type: .pushNotification)
            await onToken(mockToken)
        },
        pushToStartTokenUpdates: { _ in },
        hasActiveActivities: { true },
        endFireplaceQuestion: { }
    )
}

#if os(iOS)
@preconcurrency import ActivityKit
import UIKit

private let logger = Logger(label: "LiveActivityDependency")

extension LiveActivityDependency: DependencyKey {
    static let liveValue: Self = {
        return Self(
            startActivity: { initialState in
                logger.info("Starting new Live Activity", metadata: ["openCount": "\(initialState.openCount)"])
                let activity = try Activity<WindowAttributes>.request(
                    attributes: WindowAttributes(),
                    content: .init(state: initialState, staleDate: initialState.staleDate),
                    pushType: .token
                )
                logger.info("Live Activity started", metadata: ["activityId": "\(activity.id)"])
            },
            updateActivity: { newState in
                var activities = Activity<WindowAttributes>.activities
                let lastActivity = activities.popLast()

                guard let lastActivity else {
                    assertionFailure("Did not find any activity")
                    logger.error("updateActivity called but no active activities found")
                    return
                }

                logger.info("Updating Live Activity", metadata: [
                    "activityId": "\(lastActivity.id)",
                    "openCount": "\(newState.openCount)",
                    "duplicateCount": "\(activities.count)"
                ])
                await lastActivity.update(.init(state: newState, staleDate: newState.staleDate))

                for activity in activities {
                    logger.info("Ending duplicate Live Activity", metadata: ["activityId": "\(activity.id)"])
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
                    group.addTask { await observeUpdateTokens(of: WindowAttributes.self, activityName: WindowContentState.activityTypeName, onToken: onToken) }
                    group.addTask { await observeUpdateTokens(of: FireplaceAttributes.self, activityName: FireplaceContentState.activityTypeName, onToken: onToken) }
                }
            },
            pushToStartTokenUpdates: { onToken in
                // Runs directly in the caller's structured concurrency context. Each activity type has its own token.
                await withDiscardingTaskGroup { group in
                    group.addTask {
                        for await pushTokenData in Activity<WindowAttributes>.pushToStartTokenUpdates {
                            await onToken(await startToken(pushTokenData, activityName: WindowContentState.activityTypeName))
                        }
                    }
                    group.addTask {
                        for await pushTokenData in Activity<FireplaceAttributes>.pushToStartTokenUpdates {
                            await onToken(await startToken(pushTokenData, activityName: FireplaceContentState.activityTypeName))
                        }
                    }
                }
            },
            hasActiveActivities: {
                let count = Activity<WindowAttributes>.activities.count
                logger.debug("hasActiveActivities: \(count) active")
                return count > 0
            },
            endFireplaceQuestion: {
                for activity in Activity<FireplaceAttributes>.activities {
                    logger.info("Ending fireplace question", metadata: ["activityId": "\(activity.id)"])
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        )
    }()
}

/// Registers the update token of every activity of `Attributes`, the ones the server starts by push included.
/// A newer activity ends the older ones of the same type, so one per type stays.
private func observeUpdateTokens<Attributes: ActivityAttributes>(of type: Attributes.Type,
                                                                activityName: String,
                                                                onToken: @escaping @Sendable (PushToken) async -> Void) async {
    await withDiscardingTaskGroup { group in
        for await activity in Activity<Attributes>.activityUpdates {
            let totalActive = Activity<Attributes>.activities.count
            logger.info("activityUpdates emitted activity: type=\(activityName), id=\(activity.id), totalActive=\(totalActive)")

            if totalActive > 1 {
                for oldActivity in Activity<Attributes>.activities where oldActivity.id != activity.id {
                    logger.info("Ending stale Live Activity: id=\(oldActivity.id)")
                    await oldActivity.end(nil, dismissalPolicy: .immediate)
                }
            }

            group.addTask {
                for await tokenData in activity.pushTokenUpdates {
                    let tokenString = tokenData.hexadecimalString
                    logger.info("pushTokenUpdates emitted for activity \(activity.id): token=\(String(tokenString.prefix(8)))...")
                    let token = await PushToken(deviceName: PushToken.currentDeviceName,
                                                tokenString: tokenString,
                                                type: .liveActivityUpdate(activityName: activityName))
                    await onToken(token)
                }
            }
        }
    }
}

private func startToken(_ data: Data, activityName: String) async -> PushToken {
    let tokenString = data.hexadecimalString
    logger.info("pushToStartTokenUpdates emitted: type=\(activityName), token=\(String(tokenString.prefix(8)))...")
    return await PushToken(deviceName: PushToken.currentDeviceName, tokenString: tokenString, type: .liveActivityStart(activityName: activityName))
}
#else
extension LiveActivityDependency: DependencyKey {
    /// Live Activities exist on iOS only: every call does nothing.
    static let liveValue = Self(
        startActivity: { _ in },
        updateActivity: { _ in },
        stopActivity: { },
        pushTokenUpdates: { _ in },
        pushToStartTokenUpdates: { _ in },
        hasActiveActivities: { false },
        endFireplaceQuestion: { }
    )
}
#endif

// MARK: - DependencyValues Extension

extension DependencyValues {
    var liveActivity: LiveActivityDependency {
        get { self[LiveActivityDependency.self] }
        set { self[LiveActivityDependency.self] = newValue }
    }
}

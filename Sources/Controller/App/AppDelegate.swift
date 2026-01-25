//
//  AppDelegate.swift
//  FlowKit Controller
//
//  Created by Julian Kahnert on 04.03.25.
//

import ComposableArchitecture
import Foundation
import HAModels
import Logging
import Shared
#if os(iOS)
import ActivityKit
import UIKit
#endif

@MainActor
public final class AppDelegate: NSObject {
    private let logger = Logger(label: "AppDelegate")

    // TCA Root Store
    static let store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }
}

#if os(iOS)
extension AppDelegate: UIApplicationDelegate {
    public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {

        logger.info("didReceiveRemoteNotification")

        let fetchTask = Task {
            // Wait for the activity to be created by the push-to-start notification
            let activity = await Activity<WindowAttributes>.activityUpdates.makeAsyncIterator().next()
            logger.info("didReceiveRemoteNotification activity \(activity?.id ?? "")")
            guard let activity else {
                logger.error("FAILED to get activity")
                return UIBackgroundFetchResult.failed
            }

            // Wait for the push token to become available.
            // The pushToken property may be nil initially after activity creation,
            // so we need to observe pushTokenUpdates to get the token asynchronously.
            let deviceToken = await activity.pushTokenUpdates.makeAsyncIterator().next()
            guard let deviceToken else {
                logger.error("FAILED to get pushToken from pushTokenUpdates")
                return UIBackgroundFetchResult.failed
            }

            // Send the activity's update token to TCA store and wait for completion.
            // This token is used to send updates to the running Live Activity.
            let token = PushToken(deviceName: UIDevice.current.name,
                                  tokenString: deviceToken.hexadecimalString,
                                  type: .liveActivityUpdate(activityName: WindowContentState.activityTypeName))
            await Self.store.send(.registerPushToken(token)).finish()
            logger.info("didReceiveRemoteNotification registered update token successfully")

            return UIBackgroundFetchResult.newData
        }

        let timeoutTask = Task {
            try await Task.sleep(for: .seconds(5))
            fetchTask.cancel()
            logger.error("didReceiveRemoteNotification timeout while getting pushToken")
            assertionFailure()
        }

        let result = await fetchTask.value
        timeoutTask.cancel()

        logger.info("didReceiveRemoteNotification complete")
        return result
    }

    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.info("Registered for remote notifications")
        let token = PushToken(deviceName: UIDevice.current.name,
                              tokenString: deviceToken.hexadecimalString,
                              type: .pushNotification)
        Self.store.send(.registerPushToken(token))
    }

    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        logger.critical("Failed to register for remote notifications: \(error)")
    }
}
#else
import AppKit

extension AppDelegate: NSApplicationDelegate {
}
#endif

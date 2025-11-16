//
//  AppDelegate.swift
//  FlowKit Controller
//
//  Created by Julian Kahnert on 04.03.25.
//

import ComposableArchitecture
import Controller
import Foundation
import Logging
#if os(iOS)
import ActivityKit
import UIKit
#else
import AppKit
#endif

@MainActor
class AppDelegate: NSObject {
    private let logger = Logger(label: "AppDelegate")

    // TCA Store
    private(set) lazy var store = Store(initialState: AppFeature.State()) {
        AppFeature()
    }

    override init() {
        super.init()
    }
}

#if canImport(UIKit)
extension AppDelegate: UIApplicationDelegate {
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {

        logger.info("didReceiveRemoteNotification")

        let fetchTask = Task {
            let activity = await Activity<WindowAttributes>.activityUpdates.makeAsyncIterator().next()
            logger.info("didReceiveRemoteNotification activity \(activity?.id ?? "")")
            guard let activity,
                  let token = activity.pushToken else {
                logger.error("FAILED to get pushToken")
                return UIBackgroundFetchResult.failed
            }

            // Send token to TCA store
            await store.send(.liveActivityPushTokenReceived(token)).finish()

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

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.info("Registered for remote notifications")
        store.send(.deviceTokenReceived(deviceToken))
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        logger.critical("Failed to register for remote notifications: \(error)")
    }
}
#else
extension AppDelegate: NSApplicationDelegate {
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.info("Registered for remote notifications")
        store.send(.deviceTokenReceived(deviceToken))
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        logger.critical("Failed to register for remote notifications: \(error)")
    }
}
#endif

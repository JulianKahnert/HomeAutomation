//
//  AppDelegate.swift
//  FlowKit Controller
//
//  Created by Julian Kahnert on 04.03.25.
//

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

    private(set) var appState = AppState()

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
            await appState.send(pushToken: token, ofType: .liveActivityUpdate(activityName: String(describing: activity.self)))
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
        Task {
            await appState.send(pushToken: deviceToken, ofType: .pushNotification)
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        logger.critical("Failed to register for remote notifications: \(error)")
    }
}
#else
extension AppDelegate: NSApplicationDelegate {
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task {
            await appState.send(pushToken: deviceToken, ofType: .pushNotification)
        }
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        logger.critical("Failed to register for remote notifications: \(error)")
    }
}
#endif

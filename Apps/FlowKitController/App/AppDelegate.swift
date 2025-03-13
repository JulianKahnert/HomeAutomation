//
//  AppDelegate.swift
//  FlowKit Controller
//
//  Created by Julian Kahnert on 04.03.25.
//

import Foundation
import Logging
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
import ActivityKit

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

//        for activity in Activity<WindowOpenAttributes>.activities {
        let activity = await Activity<WindowOpenAttributes>.activityUpdates.makeAsyncIterator().next()
        logger.info("didReceiveRemoteNotification activity \(activity?.id)")
            guard let activity,
                  let token = activity.pushToken else {
                logger.error("FAILED to get pushToken")
                return .failed
            }
        await appState.send(pushToken: token, ofType: .liveActivityUpdate(activityName: String(describing: activity.self)))
//        }

        logger.info("didReceiveRemoteNotification complete")
        return .newData
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task {
//            let tmp = WindowOpenAttributes.ContentState.WindowState(name: "window1", opened: Date(), maxOpenDuration: 60)
//            let data = try! JSONEncoder().encode(tmp)
//            print(String(data: data, encoding: .utf8))
//            
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

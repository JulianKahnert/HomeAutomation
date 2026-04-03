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
import UserNotifications
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
    public func application(_ application: UIApplication,
                           didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        logger.info("App launched (may be foreground or background)")

        // CRITICAL: Start token observation immediately, even if app launches in background.
        // This is required for push-to-start Live Activities to work correctly.
        // When the app is launched via push-to-start, it starts in the background and
        // the SwiftUI scene phase observer (.onSceneChange) is never triggered because
        // no view is created. By starting observation here, we ensure tokens are registered
        // regardless of how the app was launched.
        Self.store.send(.startMonitoringLiveActivities)

        return true
    }

    public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        logger.info("didReceiveRemoteNotification called")

        // Background push sent by the server when a window closes.
        // Remove the matching "window open" notification identified by its threadIdentifier.
        if let clearId = userInfo["clearNotificationId"] as? String {
            logger.info("Clearing notification with threadIdentifier: \(clearId)")
            let center = UNUserNotificationCenter.current()
            let delivered = await center.deliveredNotifications()
            let idsToRemove = delivered
                .filter { $0.request.content.threadIdentifier == clearId }
                .map(\.request.identifier)
            if !idsToRemove.isEmpty {
                center.removeDeliveredNotifications(withIdentifiers: idsToRemove)
                logger.info("Removed \(idsToRemove.count) notification(s)")
            }
            return .newData
        }

        return .noData
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

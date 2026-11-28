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
extension AppDelegate: UNUserNotificationCenterDelegate {
    /// The action "Turn off radiators" of the push "Kamin an?": switches the fireplace on through the
    /// server. It does not open the app; the call finishes before the system suspends it again.
    public nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let isOn = FireplaceNotification.requestedState(forAction: response.actionIdentifier) else { return }
        await Self.store.send(.heating(.setFireplace(isOn))).finish()
    }
}

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

        // The push "Kamin an?" brings an action along; the category has to be known before it arrives.
        UNUserNotificationCenter.current().setNotificationCategories([FireplaceNotification.category])
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        logger.info("Registered for remote notifications")
        let token = PushToken(deviceName: PushToken.currentDeviceName,
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

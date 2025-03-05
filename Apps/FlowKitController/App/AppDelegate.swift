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

@MainActor
class AppDelegate: NSObject {
    private let logger = Logger(label: "AppDelegate")

    override init() {
        super.init()
    }

    private func register(deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        logger.info("Did register for remote notifications \(tokenString)")

        Task {
            do {
                guard let url = UserDefaults.standard.url(forKey: FlowKitClient.userDefaultsKey) else {
                    logger.critical("Failed to get client URL")
                    assertionFailure()
                    return
                }
                let client = FlowKitClient(url: url)
                try await client.register(pushDeviceToken: tokenString)
            } catch {
                logger.critical("Failed to register push device \(error)")
                assertionFailure()
            }
        }
    }
}

#if canImport(UIKit)
extension AppDelegate: UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        register(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        logger.critical("Failed to register for remote notifications: \(error)")
    }
}
#else
extension AppDelegate: NSApplicationDelegate {
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        register(deviceToken: deviceToken)
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        logger.critical("Failed to register for remote notifications: \(error)")
    }
}
#endif

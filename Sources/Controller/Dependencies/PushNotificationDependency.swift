//
//  PushNotificationDependency.swift
//  ControllerFeatures
//
//  Dependency wrapper for Push Notifications management
//

import Dependencies
import DependenciesMacros
import Foundation
import HAModels

// MARK: - PushNotification Dependency

@DependencyClient
struct PushNotificationDependency: Sendable {
    /// Request authorization for push notifications
    var requestAuthorization: @Sendable () async throws -> Void

    /// Clear all delivered notifications
    var clearDeliveredNotifications: @Sendable () async -> Void
}

// MARK: - Dependency Key Implementation

extension PushNotificationDependency: TestDependencyKey {
    static let testValue = Self(
        requestAuthorization: { },
        clearDeliveredNotifications: { }
    )

    static let previewValue = Self(
        requestAuthorization: { },
        clearDeliveredNotifications: { }
    )
}

#if os(iOS)
import UIKit
import UserNotifications

extension PushNotificationDependency: DependencyKey {
    static let liveValue: Self = {
        return Self(
            requestAuthorization: {
                try await UNUserNotificationCenter.current().requestAuthorization(options: [.provisional])
                await UIApplication.shared.registerForRemoteNotifications()
            },
            clearDeliveredNotifications: {
                await UNUserNotificationCenter.current().removeAllDeliveredNotifications()
            }
        )
    }()
}
#else
extension PushNotificationDependency: DependencyKey {
    static let liveValue = Self(
        requestAuthorization: { },
        clearDeliveredNotifications: { }
    )
}
#endif

// MARK: - DependencyValues Extension

extension DependencyValues {
    var pushNotification: PushNotificationDependency {
        get { self[PushNotificationDependency.self] }
        set { self[PushNotificationDependency.self] = newValue }
    }
}

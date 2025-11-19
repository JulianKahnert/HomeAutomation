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
}

// MARK: - Dependency Key Implementation

extension PushNotificationDependency: TestDependencyKey {
    static let testValue = Self(
        requestAuthorization: { },
    )

    static let previewValue = Self(
        requestAuthorization: { },
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
            }
        )
    }()
}
#else
extension PushNotificationDependency: DependencyKey {
    static let liveValue = Self()
}
#endif

// MARK: - DependencyValues Extension

extension DependencyValues {
    var pushNotification: PushNotificationDependency {
        get { self[PushNotificationDependency.self] }
        set { self[PushNotificationDependency.self] = newValue }
    }
}

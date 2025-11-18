//
//  PushNotificationDependency.swift
//  ControllerFeatures
//
//  Dependency wrapper for Push Notifications management
//

#if os(iOS)
import Dependencies
import DependenciesMacros
import Foundation
import HAModels
import UIKit
import UserNotifications

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

// MARK: - DependencyValues Extension

extension DependencyValues {
    var pushNotification: PushNotificationDependency {
        get { self[PushNotificationDependency.self] }
        set { self[PushNotificationDependency.self] = newValue }
    }
}
#else
// MARK: - Stub for non-iOS platforms

import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct PushNotificationDependency: Sendable {
    var requestAuthorization: @Sendable () async throws -> Void
}

extension PushNotificationDependency: TestDependencyKey {
    static let testValue = Self()
    static let previewValue = Self()
}

extension PushNotificationDependency: DependencyKey {
    static let liveValue = Self()
}

extension DependencyValues {
    var pushNotification: PushNotificationDependency {
        get { self[PushNotificationDependency.self] }
        set { self[PushNotificationDependency.self] = newValue }
    }
}
#endif

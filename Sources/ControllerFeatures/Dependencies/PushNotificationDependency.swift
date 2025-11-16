//
//  PushNotificationDependency.swift
//  ControllerFeatures
//
//  Dependency wrapper for Push Notifications management
//

import Dependencies
import DependenciesMacros
import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Push Notification Types

/// Type of push notification token
public enum PushNotificationTokenType: Sendable, Equatable {
    case deviceToken
    case liveActivityStart
    case liveActivityUpdate(activityName: String)
}

/// Result of push notification registration
public enum PushNotificationRegistrationResult: Sendable, Equatable {
    case success(Data)
    case failure(Error)

    public static func == (lhs: PushNotificationRegistrationResult, rhs: PushNotificationRegistrationResult) -> Bool {
        switch (lhs, rhs) {
        case (.success(let lData), .success(let rData)):
            return lData == rData
        case (.failure, .failure):
            return true
        default:
            return false
        }
    }
}

/// Received remote notification data
public struct RemoteNotification: Sendable, Equatable {
    public let userInfo: [String: String]
    public let receivedAt: Date

    public init(userInfo: [String: String], receivedAt: Date = Date()) {
        self.userInfo = userInfo
        self.receivedAt = receivedAt
    }
}

// MARK: - PushNotification Dependency

@DependencyClient
public struct PushNotificationDependency: Sendable {
    /// Request authorization for push notifications
    public var requestAuthorization: @Sendable () async throws -> Bool

    /// Register for remote notifications
    public var register: @Sendable () async -> Void

    /// Unregister from remote notifications
    public var unregister: @Sendable () async -> Void

    /// Stream of device token updates
    public var deviceTokenUpdates: @Sendable () async -> AsyncStream<Data> = { .finished }

    /// Stream of registration failures
    public var registrationFailures: @Sendable () async -> AsyncStream<Error> = { .finished }

    /// Stream of received remote notifications
    public var notificationReceived: @Sendable () async -> AsyncStream<RemoteNotification> = { .finished }

    /// Check if notifications are currently authorized
    public var isAuthorized: @Sendable () async -> Bool = { false }

    /// Get the current device token (if available)
    public var currentDeviceToken: @Sendable () async -> Data? = { nil }
}

// MARK: - Dependency Key Implementation

extension PushNotificationDependency: TestDependencyKey {
    public static let testValue = Self(
        requestAuthorization: { false },
        register: { },
        unregister: { },
        deviceTokenUpdates: { .finished },
        registrationFailures: { .finished },
        notificationReceived: { .finished },
        isAuthorized: { false },
        currentDeviceToken: { nil }
    )

    public static let previewValue = Self(
        requestAuthorization: { true },
        register: { },
        unregister: { },
        deviceTokenUpdates: {
            AsyncStream { continuation in
                // Simulate a device token
                let mockToken = Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
                continuation.yield(mockToken)
                continuation.finish()
            }
        },
        registrationFailures: { .finished },
        notificationReceived: {
            AsyncStream { continuation in
                let mockNotification = RemoteNotification(
                    userInfo: ["type": "window_update"],
                    receivedAt: Date()
                )
                continuation.yield(mockNotification)
                continuation.finish()
            }
        },
        isAuthorized: { true },
        currentDeviceToken: { Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]) }
    )
}

extension PushNotificationDependency: DependencyKey {
    public static let liveValue: Self = {
        // Shared state for live implementation
        actor PushNotificationState {
            var deviceToken: Data?
            var deviceTokenContinuation: AsyncStream<Data>.Continuation?
            var registrationFailureContinuation: AsyncStream<Error>.Continuation?
            var notificationContinuation: AsyncStream<RemoteNotification>.Continuation?

            func setDeviceToken(_ token: Data) {
                self.deviceToken = token
                deviceTokenContinuation?.yield(token)
            }

            func setRegistrationFailure(_ error: Error) {
                registrationFailureContinuation?.yield(error)
            }

            func setNotification(_ notification: RemoteNotification) {
                notificationContinuation?.yield(notification)
            }

            func setDeviceTokenContinuation(_ continuation: AsyncStream<Data>.Continuation?) {
                self.deviceTokenContinuation = continuation
            }

            func setRegistrationFailureContinuation(_ continuation: AsyncStream<Error>.Continuation?) {
                self.registrationFailureContinuation = continuation
            }

            func setNotificationContinuation(_ continuation: AsyncStream<RemoteNotification>.Continuation?) {
                self.notificationContinuation = continuation
            }
        }

        let state = PushNotificationState()

        return Self(
            requestAuthorization: {
                #if canImport(UserNotifications)
                try await withCheckedThrowingContinuation { continuation in
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
                #else
                false
                #endif
            },
            register: {
                #if canImport(UIKit)
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                #elseif canImport(AppKit)
                await MainActor.run {
                    NSApplication.shared.registerForRemoteNotifications()
                }
                #endif
            },
            unregister: {
                #if canImport(UIKit)
                await MainActor.run {
                    UIApplication.shared.unregisterForRemoteNotifications()
                }
                #elseif canImport(AppKit)
                await MainActor.run {
                    NSApplication.shared.unregisterForRemoteNotifications()
                }
                #endif
            },
            deviceTokenUpdates: {
                AsyncStream { continuation in
                    Task {
                        await state.setDeviceTokenContinuation(continuation)
                    }
                    continuation.onTermination = { @Sendable _ in
                        Task {
                            await state.setDeviceTokenContinuation(nil)
                        }
                    }
                }
            },
            registrationFailures: {
                AsyncStream { continuation in
                    Task {
                        await state.setRegistrationFailureContinuation(continuation)
                    }
                    continuation.onTermination = { @Sendable _ in
                        Task {
                            await state.setRegistrationFailureContinuation(nil)
                        }
                    }
                }
            },
            notificationReceived: {
                AsyncStream { continuation in
                    Task {
                        await state.setNotificationContinuation(continuation)
                    }
                    continuation.onTermination = { @Sendable _ in
                        Task {
                            await state.setNotificationContinuation(nil)
                        }
                    }
                }
            },
            isAuthorized: {
                #if canImport(UserNotifications)
                let settings = await UNUserNotificationCenter.current().notificationSettings()
                return settings.authorizationStatus == .authorized
                #else
                false
                #endif
            },
            currentDeviceToken: {
                await state.deviceToken
            }
        )
    }()
}

// MARK: - DependencyValues Extension

public extension DependencyValues {
    var pushNotification: PushNotificationDependency {
        get { self[PushNotificationDependency.self] }
        set { self[PushNotificationDependency.self] = newValue }
    }
}

// MARK: - Helper for AppDelegate Integration

/// Bridge for connecting AppDelegate push notification callbacks to the dependency
public struct PushNotificationBridge {
    private let dependency: PushNotificationDependency

    public init(dependency: PushNotificationDependency) {
        self.dependency = dependency
    }

    /// Call this from AppDelegate's didRegisterForRemoteNotificationsWithDeviceToken
    public func didRegisterForRemoteNotifications(deviceToken: Data) async {
        // This will be implemented when we integrate with AppDelegate
        // The dependency's deviceTokenUpdates stream will yield the token
    }

    /// Call this from AppDelegate's didFailToRegisterForRemoteNotificationsWithError
    public func didFailToRegisterForRemoteNotifications(error: Error) async {
        // This will be implemented when we integrate with AppDelegate
        // The dependency's registrationFailures stream will yield the error
    }

    /// Call this from AppDelegate's didReceiveRemoteNotification
    public func didReceiveRemoteNotification(userInfo: [AnyHashable: Any]) async {
        // This will be implemented when we integrate with AppDelegate
        let stringUserInfo = userInfo.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String, let value = pair.value as? String {
                result[key] = value
            }
        }
        _ = RemoteNotification(userInfo: stringUserInfo)
        // The dependency's notificationReceived stream will yield the notification
    }
}

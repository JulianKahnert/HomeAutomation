//
//  PushNotificationDependencyTests.swift
//  ControllerFeaturesTests
//
//  Tests for PushNotification dependency
//

@testable import Controller
import Dependencies
import Foundation
import Testing

@Suite("PushNotification Dependency Tests")
struct PushNotificationDependencyTests {

    @Test("Test value returns default values")
    func testTestValue() async throws {
        try await withDependencies {
            $0.pushNotification = .testValue
        } operation: {
            @Dependency(\.pushNotification) var pushNotification

            let isAuthorized = try await pushNotification.requestAuthorization()
            #expect(isAuthorized == false)

            let deviceTokenStream = await pushNotification.deviceTokenUpdates()
            var tokenCount = 0
            for await _ in deviceTokenStream {
                tokenCount += 1
            }
            #expect(tokenCount == 0)

            let failureStream = await pushNotification.registrationFailures()
            var failureCount = 0
            for await _ in failureStream {
                failureCount += 1
            }
            #expect(failureCount == 0)

            let notificationStream = await pushNotification.notificationReceived()
            var notificationCount = 0
            for await _ in notificationStream {
                notificationCount += 1
            }
            #expect(notificationCount == 0)

            let authorized = await pushNotification.isAuthorized()
            #expect(authorized == false)

            let token = await pushNotification.currentDeviceToken()
            #expect(token == nil)
        }
    }

    @Test("Preview value returns mock data")
    func testPreviewValue() async throws {
        try await withDependencies {
            $0.pushNotification = .previewValue
        } operation: {
            @Dependency(\.pushNotification) var pushNotification

            let isAuthorized = try await pushNotification.requestAuthorization()
            #expect(isAuthorized == true)

            let deviceTokenStream = await pushNotification.deviceTokenUpdates()
            var tokens: [Data] = []
            for await token in deviceTokenStream {
                tokens.append(token)
            }
            #expect(tokens.count == 1)
            #expect(tokens[0] == Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]))

            let notificationStream = await pushNotification.notificationReceived()
            var notifications: [RemoteNotification] = []
            for await notification in notificationStream {
                notifications.append(notification)
            }
            #expect(notifications.count == 1)
            #expect(notifications[0].userInfo["type"] == "window_update")

            let authorized = await pushNotification.isAuthorized()
            #expect(authorized == true)

            let token = await pushNotification.currentDeviceToken()
            #expect(token == Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF]))
        }
    }

    @Test("Register/unregister operations don't throw")
    func testOperations() async throws {
        try await withDependencies {
            $0.pushNotification = .previewValue
        } operation: {
            @Dependency(\.pushNotification) var pushNotification

            await pushNotification.register()
            await pushNotification.unregister()
        }
    }

    @Test("RemoteNotification equality works correctly")
    func testRemoteNotificationEquality() {
        let notification1 = RemoteNotification(
            userInfo: ["key": "value"],
            receivedAt: Date(timeIntervalSince1970: 1000)
        )
        let notification2 = RemoteNotification(
            userInfo: ["key": "value"],
            receivedAt: Date(timeIntervalSince1970: 1000)
        )
        let notification3 = RemoteNotification(
            userInfo: ["key": "different"],
            receivedAt: Date(timeIntervalSince1970: 1000)
        )

        #expect(notification1 == notification2)
        #expect(notification1 != notification3)
    }

    @Test("PushNotificationRegistrationResult equality works correctly")
    func testRegistrationResultEquality() {
        let token = Data([0x01, 0x02, 0x03])
        let success1 = PushNotificationRegistrationResult.success(token)
        let success2 = PushNotificationRegistrationResult.success(token)
        let success3 = PushNotificationRegistrationResult.success(Data([0x04, 0x05]))

        #expect(success1 == success2)
        #expect(success1 != success3)

        let error = NSError(domain: "test", code: 1)
        let failure1 = PushNotificationRegistrationResult.failure(error)
        let failure2 = PushNotificationRegistrationResult.failure(error)

        #expect(failure1 == failure2)
        #expect(success1 != failure1)
    }
}

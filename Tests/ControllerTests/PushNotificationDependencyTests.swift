//
//  PushNotificationDependencyTests.swift
//  ControllerFeaturesTests
//
//  Tests for PushNotification dependency
//

#if os(iOS)
@testable import Controller
import Dependencies
import Foundation
import Testing

@Suite("PushNotification Dependency Tests")
struct PushNotificationDependencyTests {

    @Test("Test value doesn't throw")
    func testTestValue() async throws {
        try await withDependencies {
            $0.pushNotification = .testValue
        } operation: {
            @Dependency(\.pushNotification) var pushNotification

            try await pushNotification.requestAuthorization()
        }
    }

    @Test("Preview value doesn't throw")
    func testPreviewValue() async throws {
        try await withDependencies {
            $0.pushNotification = .previewValue
        } operation: {
            @Dependency(\.pushNotification) var pushNotification

            try await pushNotification.requestAuthorization()
        }
    }
}
#endif

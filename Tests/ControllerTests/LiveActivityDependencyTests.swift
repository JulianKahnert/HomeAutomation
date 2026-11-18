//
//  LiveActivityDependencyTests.swift
//  ControllerFeaturesTests
//
//  Tests for LiveActivity dependency
//

#if os(iOS)
@testable import Controller
import Dependencies
import Foundation
import HAModels
import Testing

@Suite("LiveActivity Dependency Tests")
struct LiveActivityDependencyTests {

    @Test("Test value completes immediately")
    func testTestValue() async throws {
        try await withDependencies {
            $0.liveActivity = .testValue
        } operation: {
            @Dependency(\.liveActivity) var liveActivity

            // Callback-based: testValue closure body is empty, returns immediately
            let tokenCount = LockIsolated(0)
            await liveActivity.pushTokenUpdates { _ in
                tokenCount.withValue { $0 += 1 }
            }
            #expect(tokenCount.value == 0)

            let hasActive = await liveActivity.hasActiveActivities()
            #expect(hasActive == false)
        }
    }

    @Test("Preview value returns mock data")
    func testPreviewValue() async throws {
        try await withDependencies {
            $0.liveActivity = .previewValue
        } operation: {
            @Dependency(\.liveActivity) var liveActivity

            let tokens = LockIsolated<[PushToken]>([])
            await liveActivity.pushTokenUpdates { token in
                tokens.withValue { $0.append(token) }
            }
            #expect(tokens.value.count == 1)
            #expect(tokens.value.first?.deviceName == "preview")
            #expect(tokens.value.first?.tokenString == "1234")

            let hasActive = await liveActivity.hasActiveActivities()
            #expect(hasActive == true)
        }
    }

    @Test("Start/update/stop operations don't throw")
    func testOperations() async throws {
        try await withDependencies {
            $0.liveActivity = .previewValue
        } operation: {
            @Dependency(\.liveActivity) var liveActivity

            let opened = Date()
            let window = WindowContentState.Window(
                id: WindowContentState.Window.id(room: "Test", name: "Window"),
                name: "Window",
                room: "Test",
                opened: opened,
                closeBy: opened.addingTimeInterval(3600),
                isOverdue: false
            )
            let contentState = WindowContentState(windows: [window], openCount: 1, overdueCount: 0)

            try await liveActivity.startActivity(contentState)
            await liveActivity.updateActivity(contentState)
            await liveActivity.stopActivity()
        }
    }
}
#endif

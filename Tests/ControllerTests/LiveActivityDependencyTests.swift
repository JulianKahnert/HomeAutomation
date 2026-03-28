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
            var tokenCount = 0
            await liveActivity.pushTokenUpdates { _ in
                tokenCount += 1
            }
            #expect(tokenCount == 0)

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

            var tokens: [PushToken] = []
            await liveActivity.pushTokenUpdates { token in
                tokens.append(token)
            }
            #expect(tokens.count == 1)
            #expect(tokens[0].deviceName == "preview")
            #expect(tokens[0].tokenString == "1234")

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

            let windowState = WindowContentState.WindowState(
                name: "Test Window",
                opened: Date(),
                maxOpenDuration: 3600
            )

            try await liveActivity.startActivity([windowState])
            await liveActivity.updateActivity([windowState])
            await liveActivity.stopActivity()
        }
    }
}
#endif

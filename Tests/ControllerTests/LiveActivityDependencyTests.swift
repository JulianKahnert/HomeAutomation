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

    @Test("Test value returns finished streams")
    func testTestValue() async throws {
        try await withDependencies {
            $0.liveActivity = .testValue
        } operation: {
            @Dependency(\.liveActivity) var liveActivity

            let tokenStream = await liveActivity.pushTokenUpdates()
            var tokenCount = 0
            for await _ in tokenStream {
                tokenCount += 1
            }
            #expect(tokenCount == 0)

            let hasActive = await liveActivity.hasActiveActivities()
            #expect(hasActive == false)

            let state = await liveActivity.currentActivityState()
            #expect(state == nil)
        }
    }

    @Test("Preview value returns mock data")
    func testPreviewValue() async throws {
        try await withDependencies {
            $0.liveActivity = .previewValue
        } operation: {
            @Dependency(\.liveActivity) var liveActivity

            let tokenStream = await liveActivity.pushTokenUpdates()
            var tokens: [Data] = []
            for await token in tokenStream {
                tokens.append(token)
            }
            #expect(tokens.count == 1)
            #expect(tokens[0] == Data([0x01, 0x02, 0x03, 0x04]))

            let contentStream = await liveActivity.contentUpdates()
            var contents: [WindowContentState] = []
            for await content in contentStream {
                contents.append(content)
            }
            #expect(contents.count == 1)
            #expect(contents[0].windowStates.count == 1)
            #expect(contents[0].windowStates[0].name == "Preview Window")

            let hasActive = await liveActivity.hasActiveActivities()
            #expect(hasActive == true)

            let state = await liveActivity.currentActivityState()
            #expect(state != nil)
            #expect(state?.windowStates.count == 1)
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

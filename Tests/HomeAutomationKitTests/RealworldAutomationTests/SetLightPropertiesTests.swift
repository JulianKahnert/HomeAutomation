//
//  SetLightPropertiesTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 10.01.26.
//

import Foundation
@testable import HAImplementations
@testable import HAModels
import Testing

@HomeManagerActor
struct SetLightPropertiesTests {
    let light1 = SwitchDevice(
        switchId: EntityId(placeId: "room1", name: "light1", characteristicsName: nil, characteristic: .switcher),
        brightnessId: EntityId(placeId: "room1", name: "light1", characteristicsName: nil, characteristic: .brightness),
        colorTemperatureId: EntityId(placeId: "room1", name: "light1", characteristicsName: nil, characteristic: .colorTemperature),
        rgbId: EntityId(placeId: "room1", name: "light1", characteristicsName: nil, characteristic: .color)
    )
    let light2 = SwitchDevice(
        switchId: EntityId(placeId: "room1", name: "light2", characteristicsName: nil, characteristic: .switcher),
        brightnessId: EntityId(placeId: "room1", name: "light2", characteristicsName: nil, characteristic: .brightness),
        colorTemperatureId: EntityId(placeId: "room1", name: "light2", characteristicsName: nil, characteristic: .colorTemperature),
        rgbId: EntityId(placeId: "room1", name: "light2", characteristicsName: nil, characteristic: .color)
    )

    @Test("Test with only RGB set")
    func executeWithOnlyRGB() async throws {
        let automation = SetLightProperties(
            "set-rgb-only",
            at: Time(hour: 20, minute: 0),
            lights: [light1, light2],
            targetColor: RGB(red: 1.0, green: 0.5, blue: 0.3),
            targetColorTemperature: nil,
            targetBrightness: nil,
            delayBetweenProperties: .milliseconds(10)
        )

        let mockAdapter = MockHomeAdapter()
        try await automation.execute(using: mockAdapter)

        let traceMap = mockAdapter.getSortedTraceMap()

        // Should call setRGB for both lights
        #expect(traceMap.contains("action.setRGB: 2"))
        // Should not call setColorTemperature or setBrightness
        #expect(!traceMap.contains { $0.contains("setColorTemperature") })
        #expect(!traceMap.contains { $0.contains("setBrightness") })
    }

    @Test("Test with only color temperature set")
    func executeWithOnlyColorTemperature() async throws {
        let automation = SetLightProperties(
            "set-color-temp-only",
            at: Time(hour: 20, minute: 0),
            lights: [light1, light2],
            targetColor: nil,
            targetColorTemperature: 3000,
            targetBrightness: nil,
            delayBetweenProperties: .milliseconds(10)
        )

        let mockAdapter = MockHomeAdapter()
        try await automation.execute(using: mockAdapter)

        let traceMap = mockAdapter.getSortedTraceMap()

        // Should call setColorTemperature for both lights
        #expect(traceMap.contains("action.setColorTemperature: 2"))
        // Should not call setRGB or setBrightness
        #expect(!traceMap.contains { $0.contains("setRGB") })
        #expect(!traceMap.contains { $0.contains("setBrightness") })
    }

    @Test("Test with only brightness set")
    func executeWithOnlyBrightness() async throws {
        let automation = SetLightProperties(
            "set-brightness-only",
            at: Time(hour: 20, minute: 0),
            lights: [light1, light2],
            targetColor: nil,
            targetColorTemperature: nil,
            targetBrightness: 75,
            delayBetweenProperties: .milliseconds(10)
        )

        let mockAdapter = MockHomeAdapter()
        try await automation.execute(using: mockAdapter)

        let traceMap = mockAdapter.getSortedTraceMap()

        // Should call setBrightness for both lights
        #expect(traceMap.contains("action.setBrightness: 2"))
        // Should not call setRGB or setColorTemperature
        #expect(!traceMap.contains { $0.contains("setRGB") })
        #expect(!traceMap.contains { $0.contains("setColorTemperature") })
    }

    @Test("Test with all properties set")
    func executeWithAllPropertiesSet() async throws {
        let automation = SetLightProperties(
            "set-all-properties",
            at: Time(hour: 20, minute: 0),
            lights: [light1, light2],
            targetColor: RGB(red: 1.0, green: 0.8, blue: 0.6),
            targetColorTemperature: 2700,
            targetBrightness: 80,
            delayBetweenProperties: .milliseconds(10)
        )

        let mockAdapter = MockHomeAdapter()
        try await automation.execute(using: mockAdapter)

        let traceMap = mockAdapter.getSortedTraceMap()

        // Should call all three actions for both lights
        #expect(traceMap.contains("action.setRGB: 2"))
        #expect(traceMap.contains("action.setColorTemperature: 2"))
        #expect(traceMap.contains("action.setBrightness: 2"))
    }

    @Test("Test with no optional properties set (should do nothing)")
    func executeWithNoOptionalProperties() async throws {
        let automation = SetLightProperties(
            "set-nothing",
            at: Time(hour: 20, minute: 0),
            lights: [light1, light2],
            targetColor: nil,
            targetColorTemperature: nil,
            targetBrightness: nil,
            delayBetweenProperties: .milliseconds(10)
        )

        let mockAdapter = MockHomeAdapter()
        try await automation.execute(using: mockAdapter)

        let traceMap = mockAdapter.getSortedTraceMap()

        // Should not perform any actions
        #expect(!traceMap.contains { $0.contains("setRGB") })
        #expect(!traceMap.contains { $0.contains("setColorTemperature") })
        #expect(!traceMap.contains { $0.contains("setBrightness") })
    }

    @Test("Test that delays are applied between property types")
    func executeWithDelaysBetweenProperties() async throws {
        let delayDuration: Duration = .milliseconds(50)
        let automation = SetLightProperties(
            "test-delays",
            at: Time(hour: 20, minute: 0),
            lights: [light1],
            targetColor: RGB(red: 1.0, green: 1.0, blue: 1.0),
            targetColorTemperature: 3000,
            targetBrightness: 100,
            delayBetweenProperties: delayDuration
        )

        let mockAdapter = MockHomeAdapter()
        let startTime = ContinuousClock.now
        try await automation.execute(using: mockAdapter)
        let endTime = ContinuousClock.now
        let elapsed = endTime - startTime

        // Should take at least 2 * delayDuration (after RGB, after color temp)
        // We use a slightly lower threshold to account for execution time variability
        let expectedMinDuration = delayDuration * 2
        #expect(elapsed >= expectedMinDuration - .milliseconds(10))
    }

    @Test("Test parallel execution within property groups")
    func executeParallelWithinPropertyGroups() async throws {
        // Create many lights to test parallel execution
        let manyLights = (1...10).map { i in
            SwitchDevice(
                switchId: EntityId(placeId: "room1", name: "light\(i)", characteristicsName: nil, characteristic: .switcher),
                brightnessId: EntityId(placeId: "room1", name: "light\(i)", characteristicsName: nil, characteristic: .brightness),
                colorTemperatureId: EntityId(placeId: "room1", name: "light\(i)", characteristicsName: nil, characteristic: .colorTemperature),
                rgbId: EntityId(placeId: "room1", name: "light\(i)", characteristicsName: nil, characteristic: .color)
            )
        }

        let automation = SetLightProperties(
            "test-parallel",
            at: Time(hour: 20, minute: 0),
            lights: manyLights,
            targetColor: RGB(red: 1.0, green: 1.0, blue: 1.0),
            targetColorTemperature: nil,
            targetBrightness: nil,
            delayBetweenProperties: .milliseconds(10)
        )

        let mockAdapter = MockHomeAdapter()
        try await automation.execute(using: mockAdapter)

        let traceMap = mockAdapter.getSortedTraceMap()

        // Should call setRGB for all lights
        #expect(traceMap.contains("action.setRGB: 10"))
    }

    @Test("Test shouldTrigger with matching time")
    func testShouldTriggerWithMatchingTime() async throws {
        let automation = SetLightProperties(
            "test-trigger",
            at: Time(hour: 20, minute: 30),
            lights: [light1],
            targetColor: RGB(red: 1.0, green: 1.0, blue: 1.0),
            targetColorTemperature: nil,
            targetBrightness: nil
        )

        let mockAdapter = MockHomeAdapter()

        // Create a date at exactly 20:30
        var components = DateComponents()
        components.hour = 20
        components.minute = 30
        components.year = 2024
        components.month = 7
        components.day = 20
        let calendar = Calendar.current
        let correctDate = calendar.date(from: components)!
        let correctEvent = HomeEvent.time(date: correctDate)

        // Should trigger at the correct time
        let shouldTrigger = try await automation.shouldTrigger(with: correctEvent, using: mockAdapter)
        #expect(shouldTrigger == true)

        // Should not trigger at a different minute
        var incorrectComponents = DateComponents()
        incorrectComponents.hour = 20
        incorrectComponents.minute = 31
        incorrectComponents.year = 2024
        incorrectComponents.month = 7
        incorrectComponents.day = 20
        let incorrectDate = calendar.date(from: incorrectComponents)!
        let incorrectEvent = HomeEvent.time(date: incorrectDate)

        let shouldNotTrigger = try await automation.shouldTrigger(with: incorrectEvent, using: mockAdapter)
        #expect(shouldNotTrigger == false)
    }

    @Test("Test triggerEntityIds is empty")
    func testTriggerEntityIds() {
        let automation = SetLightProperties(
            "test-entity-ids",
            at: Time(hour: 20, minute: 0),
            lights: [light1, light2],
            targetColor: RGB(red: 1.0, green: 1.0, blue: 1.0),
            targetColorTemperature: nil,
            targetBrightness: nil
        )

        // SetLightProperties is time-based, not entity-based
        #expect(automation.triggerEntityIds.isEmpty)
    }

    @Test("Test color temperature value clamping")
    func testColorTemperatureClamping() async throws {
        // Test with very high color temperature (should be clamped to 1.0)
        let automationHigh = SetLightProperties(
            "test-clamp-high",
            at: Time(hour: 20, minute: 0),
            lights: [light1],
            targetColor: nil,
            targetColorTemperature: 10000,
            targetBrightness: nil,
            delayBetweenProperties: .milliseconds(10)
        )

        let mockAdapterHigh = MockHomeAdapter()
        try await automationHigh.execute(using: mockAdapterHigh)

        // Should execute without error (clamping happens internally)
        let traceMapHigh = mockAdapterHigh.getSortedTraceMap()
        #expect(traceMapHigh.contains("action.setColorTemperature: 1"))

        // Test with very low color temperature (should be clamped to 0.0)
        let automationLow = SetLightProperties(
            "test-clamp-low",
            at: Time(hour: 20, minute: 0),
            lights: [light1],
            targetColor: nil,
            targetColorTemperature: 1000,
            targetBrightness: nil,
            delayBetweenProperties: .milliseconds(10)
        )

        let mockAdapterLow = MockHomeAdapter()
        try await automationLow.execute(using: mockAdapterLow)

        let traceMapLow = mockAdapterLow.getSortedTraceMap()
        #expect(traceMapLow.contains("action.setColorTemperature: 1"))
    }

    @Test("Test brightness value clamping")
    func testBrightnessClamping() async throws {
        // Test with brightness over 100 (should be clamped to 1.0)
        let automationHigh = SetLightProperties(
            "test-brightness-high",
            at: Time(hour: 20, minute: 0),
            lights: [light1],
            targetColor: nil,
            targetColorTemperature: nil,
            targetBrightness: 150,
            delayBetweenProperties: .milliseconds(10)
        )

        let mockAdapterHigh = MockHomeAdapter()
        try await automationHigh.execute(using: mockAdapterHigh)

        let traceMapHigh = mockAdapterHigh.getSortedTraceMap()
        #expect(traceMapHigh.contains("action.setBrightness: 1"))

        // Test with negative brightness (should be clamped to 0.0)
        let automationLow = SetLightProperties(
            "test-brightness-low",
            at: Time(hour: 20, minute: 0),
            lights: [light1],
            targetColor: nil,
            targetColorTemperature: nil,
            targetBrightness: -10,
            delayBetweenProperties: .milliseconds(10)
        )

        let mockAdapterLow = MockHomeAdapter()
        try await automationLow.execute(using: mockAdapterLow)

        let traceMapLow = mockAdapterLow.getSortedTraceMap()
        #expect(traceMapLow.contains("action.setBrightness: 1"))
    }
}

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
            color: RGB(red: 1.0, green: 0.5, blue: 0.3),
            colorTemperature: nil,
            brightness: nil,
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
            color: nil,
            colorTemperature: 0.5,
            brightness: nil,
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
            color: nil,
            colorTemperature: nil,
            brightness: 0.75,
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
            color: RGB(red: 1.0, green: 0.8, blue: 0.6),
            colorTemperature: 0.35,
            brightness: 0.8,
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
            color: nil,
            colorTemperature: nil,
            brightness: nil,
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
            color: RGB(red: 1.0, green: 1.0, blue: 1.0),
            colorTemperature: 0.5,
            brightness: 1.0,
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
            color: RGB(red: 1.0, green: 1.0, blue: 1.0),
            colorTemperature: nil,
            brightness: nil,
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
            color: RGB(red: 1.0, green: 1.0, blue: 1.0),
            colorTemperature: nil,
            brightness: nil
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
            color: RGB(red: 1.0, green: 1.0, blue: 1.0),
            colorTemperature: nil,
            brightness: nil
        )

        // SetLightProperties is time-based, not entity-based
        #expect(automation.triggerEntityIds.isEmpty)
    }

    @Test("Test color temperature normalized values")
    func testColorTemperatureNormalizedValues() async throws {
        // Test with minimum value (0.0 - warmest)
        let automationMin = SetLightProperties(
            "test-min-temp",
            at: Time(hour: 20, minute: 0),
            lights: [light1],
            color: nil,
            colorTemperature: 0.0,
            brightness: nil,
            delayBetweenProperties: .milliseconds(10)
        )

        let mockAdapterMin = MockHomeAdapter()
        try await automationMin.execute(using: mockAdapterMin)

        let traceMapMin = mockAdapterMin.getSortedTraceMap()
        #expect(traceMapMin.contains("action.setColorTemperature: 1"))

        // Test with maximum value (1.0 - coolest)
        let automationMax = SetLightProperties(
            "test-max-temp",
            at: Time(hour: 20, minute: 0),
            lights: [light1],
            color: nil,
            colorTemperature: 1.0,
            brightness: nil,
            delayBetweenProperties: .milliseconds(10)
        )

        let mockAdapterMax = MockHomeAdapter()
        try await automationMax.execute(using: mockAdapterMax)

        let traceMapMax = mockAdapterMax.getSortedTraceMap()
        #expect(traceMapMax.contains("action.setColorTemperature: 1"))
    }

    @Test("Test brightness normalized values")
    func testBrightnessNormalizedValues() async throws {
        // Test with minimum value (0.0 - off)
        let automationMin = SetLightProperties(
            "test-brightness-min",
            at: Time(hour: 20, minute: 0),
            lights: [light1],
            color: nil,
            colorTemperature: nil,
            brightness: 0.0,
            delayBetweenProperties: .milliseconds(10)
        )

        let mockAdapterMin = MockHomeAdapter()
        try await automationMin.execute(using: mockAdapterMin)

        let traceMapMin = mockAdapterMin.getSortedTraceMap()
        #expect(traceMapMin.contains("action.setBrightness: 1"))

        // Test with maximum value (1.0 - maximum brightness)
        let automationMax = SetLightProperties(
            "test-brightness-max",
            at: Time(hour: 20, minute: 0),
            lights: [light1],
            color: nil,
            colorTemperature: nil,
            brightness: 1.0,
            delayBetweenProperties: .milliseconds(10)
        )

        let mockAdapterMax = MockHomeAdapter()
        try await automationMax.execute(using: mockAdapterMax)

        let traceMapMax = mockAdapterMax.getSortedTraceMap()
        #expect(traceMapMax.contains("action.setBrightness: 1"))
    }
}

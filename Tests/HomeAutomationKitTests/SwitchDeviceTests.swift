//
//  SwitchDeviceTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 06.12.25.
//

import Foundation
@testable import HAModels
import Testing

struct SwitchDeviceTests {

    @Test("Test default skipColorTemperature is false")
    func defaultSkipColorTemperature() throws {
        let device = SwitchDevice(
            switchId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .switcher),
            brightnessId: nil,
            colorTemperatureId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .colorTemperature),
            rgbId: nil
        )

        #expect(device.skipColorTemperature == false)
    }

    @Test("Test hasColorTemperatureSupport with colorTemperatureId and skip disabled")
    func hasColorTemperatureSupportWithColorTempId() throws {
        let device = SwitchDevice(
            switchId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .switcher),
            brightnessId: nil,
            colorTemperatureId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .colorTemperature),
            rgbId: nil
        )

        #expect(device.hasColorTemperatureSupport == true)
    }

    @Test("Test hasColorTemperatureSupport with rgbId and skip disabled")
    func hasColorTemperatureSupportWithRgbId() throws {
        let device = SwitchDevice(
            switchId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .switcher),
            brightnessId: nil,
            colorTemperatureId: nil,
            rgbId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .color)
        )

        #expect(device.hasColorTemperatureSupport == true)
    }

    @Test("Test hasColorTemperatureSupport returns false when skip enabled")
    func hasColorTemperatureSupportWithSkipEnabled() throws {
        let device = SwitchDevice(
            switchId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .switcher),
            brightnessId: nil,
            colorTemperatureId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .colorTemperature),
            rgbId: nil,
            skipColorTemperature: true
        )

        #expect(device.skipColorTemperature == true)
        #expect(device.hasColorTemperatureSupport == false)
    }

    @Test("Test hasColorTemperatureSupport returns false when no color support available")
    func hasColorTemperatureSupportWithNoSupport() throws {
        let device = SwitchDevice(
            switchId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .switcher),
            brightnessId: nil,
            colorTemperatureId: nil,
            rgbId: nil
        )

        #expect(device.hasColorTemperatureSupport == false)
    }

    @Test("Test setColorTemperature is skipped when skipColorTemperature is true")
    func setColorTemperatureSkippedWhenFlagEnabled() async throws {
        let device = SwitchDevice(
            switchId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .switcher),
            brightnessId: nil,
            colorTemperatureId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .colorTemperature),
            rgbId: nil,
            skipColorTemperature: true
        )

        let mockAdapter = await MockHomeAdapter()

        // Call setColorTemperature - should be skipped
        await device.setColorTemperature(to: 0.5, with: mockAdapter)

        // Verify no setColorTemperature action was performed
        let traceMap = await mockAdapter.getSortedTraceMap()
        #expect(!traceMap.contains { $0.contains("setColorTemperature") })
    }

    @Test("Test setColorTemperature works normally when skip is false")
    func setColorTemperatureWorksWhenSkipDisabled() async throws {
        let device = SwitchDevice(
            switchId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .switcher),
            brightnessId: nil,
            colorTemperatureId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .colorTemperature),
            rgbId: nil
        )

        let mockAdapter = await MockHomeAdapter()

        // Call setColorTemperature - should work normally
        await device.setColorTemperature(to: 0.5, with: mockAdapter)

        // Verify setColorTemperature action was performed
        let traceMap = await mockAdapter.getSortedTraceMap()
        #expect(traceMap.contains("action.setColorTemperature: 1"))
    }

    @Test("Test setColorTemperature with RGB fallback when skip is false")
    func setColorTemperatureWithRgbFallback() async throws {
        let device = SwitchDevice(
            switchId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .switcher),
            brightnessId: nil,
            colorTemperatureId: nil,
            rgbId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .color)
        )

        let mockAdapter = await MockHomeAdapter()

        // Call setColorTemperature - should use RGB fallback
        await device.setColorTemperature(to: 0.5, with: mockAdapter)

        // Verify setRGB action was performed (fallback)
        let traceMap = await mockAdapter.getSortedTraceMap()
        #expect(traceMap.contains("action.setRGB: 1"))
    }

    @Test("Test setColorTemperature with RGB fallback skipped when flag enabled")
    func setColorTemperatureRgbFallbackSkipped() async throws {
        let device = SwitchDevice(
            switchId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .switcher),
            brightnessId: nil,
            colorTemperatureId: nil,
            rgbId: EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .color),
            skipColorTemperature: true
        )

        let mockAdapter = await MockHomeAdapter()

        // Call setColorTemperature - should be skipped even with RGB available
        await device.setColorTemperature(to: 0.5, with: mockAdapter)

        // Verify no RGB action was performed
        let traceMap = await mockAdapter.getSortedTraceMap()
        #expect(!traceMap.contains { $0.contains("setRGB") })
    }
}

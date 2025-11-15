//
//  RoundingTests.swift
//  HomeAutomationKit
//
//  Created by Claude Code on 15.11.25.
//

import Foundation
@testable import HAModels
import Testing

struct RGBRoundingTests {

    @Test("Test RGB rounding")
    func testRGBRounding() throws {
        // Test basic rounding
        let rgb1 = RGB(red: 0.12345, green: 0.67891, blue: 0.99999)
        let rounded1 = rgb1.rounded()
        #expect(rounded1.red == 0.12)
        #expect(rounded1.green == 0.68)
        #expect(rounded1.blue == 1.0)

        // Test rounding with values that should round down
        let rgb2 = RGB(red: 0.123, green: 0.456, blue: 0.789)
        let rounded2 = rgb2.rounded()
        #expect(rounded2.red == 0.12)
        #expect(rounded2.green == 0.46)
        #expect(rounded2.blue == 0.79)

        // Test rounding with values that should round up
        let rgb3 = RGB(red: 0.125, green: 0.455, blue: 0.785)
        let rounded3 = rgb3.rounded()
        #expect(rounded3.red == 0.13)
        #expect(rounded3.green == 0.46)
        #expect(rounded3.blue == 0.79)

        // Test rounding with already rounded values (should not change)
        let rgb4 = RGB(red: 0.12, green: 0.46, blue: 0.79)
        let rounded4 = rgb4.rounded()
        #expect(rounded4.red == 0.12)
        #expect(rounded4.green == 0.46)
        #expect(rounded4.blue == 0.79)

        // Test rounding with zero values
        let rgb5 = RGB(red: 0.001, green: 0.0, blue: 0.004)
        let rounded5 = rgb5.rounded()
        #expect(rounded5.red == 0.0)
        #expect(rounded5.green == 0.0)
        #expect(rounded5.blue == 0.0)
    }
}

struct HomeManagableActionRoundingTests {
    private let testEntityId = EntityId(placeId: "test", name: "entity", characteristicsName: nil, characteristic: .brightness)

    @Test("Test setBrightness rounding")
    func testSetBrightnessRounding() throws {
        // Test rounding down
        let action1 = HomeManagableAction.setBrightness(testEntityId, 0.12345)
        let rounded1 = action1.rounded()
        guard case .setBrightness(_, let value1) = rounded1 else {
            throw TestError.unexpectedActionType
        }
        #expect(value1 == 0.12)

        // Test rounding up
        let action2 = HomeManagableAction.setBrightness(testEntityId, 0.675)
        let rounded2 = action2.rounded()
        guard case .setBrightness(_, let value2) = rounded2 else {
            throw TestError.unexpectedActionType
        }
        #expect(value2 == 0.68)

        // Test already rounded value
        let action3 = HomeManagableAction.setBrightness(testEntityId, 0.50)
        let rounded3 = action3.rounded()
        guard case .setBrightness(_, let value3) = rounded3 else {
            throw TestError.unexpectedActionType
        }
        #expect(value3 == 0.50)
    }

    @Test("Test setColorTemperature rounding")
    func testSetColorTemperatureRounding() throws {
        // Test rounding down
        let action1 = HomeManagableAction.setColorTemperature(testEntityId, 0.12345)
        let rounded1 = action1.rounded()
        guard case .setColorTemperature(_, let value1) = rounded1 else {
            throw TestError.unexpectedActionType
        }
        #expect(value1 == 0.12)

        // Test rounding up
        let action2 = HomeManagableAction.setColorTemperature(testEntityId, 0.995)
        let rounded2 = action2.rounded()
        guard case .setColorTemperature(_, let value2) = rounded2 else {
            throw TestError.unexpectedActionType
        }
        #expect(value2 == 1.0)
    }

    @Test("Test setRGB rounding")
    func testSetRGBRounding() throws {
        let rgb = RGB(red: 0.12345, green: 0.67891, blue: 0.99999)
        let action = HomeManagableAction.setRGB(testEntityId, rgb: rgb)
        let rounded = action.rounded()

        guard case .setRGB(_, let roundedRGB) = rounded else {
            throw TestError.unexpectedActionType
        }

        #expect(roundedRGB.red == 0.12)
        #expect(roundedRGB.green == 0.68)
        #expect(roundedRGB.blue == 1.0)
    }

    @Test("Test non-float actions remain unchanged")
    func testNonFloatActionsUnchanged() throws {
        // Test turnOn
        let turnOn = HomeManagableAction.turnOn(testEntityId)
        let roundedTurnOn = turnOn.rounded()
        #expect(roundedTurnOn == turnOn)

        // Test turnOff
        let turnOff = HomeManagableAction.turnOff(testEntityId)
        let roundedTurnOff = turnOff.rounded()
        #expect(roundedTurnOff == turnOff)

        // Test lockDoor
        let lockDoor = HomeManagableAction.lockDoor(testEntityId)
        let roundedLockDoor = lockDoor.rounded()
        #expect(roundedLockDoor == lockDoor)

        // Test setHeating
        let setHeating = HomeManagableAction.setHeating(testEntityId, active: true)
        let roundedSetHeating = setHeating.rounded()
        #expect(roundedSetHeating == setHeating)

        // Test setValve
        let setValve = HomeManagableAction.setValve(testEntityId, active: false)
        let roundedSetValve = setValve.rounded()
        #expect(roundedSetValve == setValve)
    }

    @Test("Test rounding prevents minor variations")
    func testRoundingPreventsMicroVariations() throws {
        // These should all round to the same value
        let values: [Float] = [0.124, 0.1241, 0.1242, 0.1243, 0.1244]

        for value in values {
            let action = HomeManagableAction.setBrightness(testEntityId, value)
            let rounded = action.rounded()

            guard case .setBrightness(_, let roundedValue) = rounded else {
                throw TestError.unexpectedActionType
            }

            #expect(roundedValue == 0.12, "Expected \(value) to round to 0.12, got \(roundedValue)")
        }

        // These should all round to 0.13
        let values2: [Float] = [0.125, 0.1251, 0.1252, 0.1253, 0.1254]

        for value in values2 {
            let action = HomeManagableAction.setBrightness(testEntityId, value)
            let rounded = action.rounded()

            guard case .setBrightness(_, let roundedValue) = rounded else {
                throw TestError.unexpectedActionType
            }

            #expect(roundedValue == 0.13, "Expected \(value) to round to 0.13, got \(roundedValue)")
        }
    }

    @Test("Test entity ID preserved after rounding")
    func testEntityIdPreservedAfterRounding() throws {
        let entityId = EntityId(placeId: "bedroom", name: "light", characteristicsName: nil, characteristic: .brightness)

        // Test with different action types
        let actions: [HomeManagableAction] = [
            .setBrightness(entityId, 0.12345),
            .setColorTemperature(entityId, 0.67891),
            .setRGB(entityId, rgb: RGB(red: 0.1, green: 0.2, blue: 0.3)),
            .turnOn(entityId),
            .turnOff(entityId)
        ]

        for action in actions {
            let rounded = action.rounded()
            #expect(rounded.entityId == entityId)
        }
    }
}

enum TestError: Error {
    case unexpectedActionType
}

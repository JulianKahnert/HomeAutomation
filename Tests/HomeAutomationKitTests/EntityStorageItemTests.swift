//
//  EntityStorageItemTests.swift
//  HomeAutomationKitTests
//
//  Created for GitHub Issue #95
//

@testable import HAModels
import XCTest

final class EntityStorageItemTests: XCTestCase {
    func testHasNoSensorData_AllNil_ReturnsTrue() {
        let entityId = EntityId(placeId: "Living Room", name: "Light", characteristicsName: nil, characteristic: .switcher)
        let item = EntityStorageItem(entityId: entityId)

        XCTAssertTrue(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithMotionDetected_ReturnsFalse() {
        let entityId = EntityId(placeId: "Living Room", name: "Motion", characteristicsName: nil, characteristic: .motionSensor)
        let item = EntityStorageItem(entityId: entityId, motionDetected: true)

        XCTAssertFalse(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithTemperature_ReturnsFalse() {
        let entityId = EntityId(placeId: "Living Room", name: "Sensor", characteristicsName: nil, characteristic: .temperatureSensor)
        let item = EntityStorageItem(entityId: entityId, temperatureInC: Measurement(value: 22.5, unit: .celsius))

        XCTAssertFalse(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithBrightness_ReturnsFalse() {
        let entityId = EntityId(placeId: "Living Room", name: "Light", characteristicsName: nil, characteristic: .brightness)
        let item = EntityStorageItem(entityId: entityId, brightness: 75)

        XCTAssertFalse(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithColor_ReturnsFalse() {
        let entityId = EntityId(placeId: "Living Room", name: "Light", characteristicsName: nil, characteristic: .color)
        let color = RGB(red: 1.0, green: 0.5, blue: 0.3)
        let item = EntityStorageItem(entityId: entityId, color: color)

        XCTAssertFalse(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithIlluminance_ReturnsFalse() {
        let entityId = EntityId(placeId: "Living Room", name: "Sensor", characteristicsName: nil, characteristic: .lightSensor)
        let item = EntityStorageItem(entityId: entityId, illuminance: Measurement(value: 100.0, unit: .lux))

        XCTAssertFalse(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithDeviceOn_ReturnsFalse() {
        let entityId = EntityId(placeId: "Living Room", name: "Light", characteristicsName: nil, characteristic: .switcher)
        let item = EntityStorageItem(entityId: entityId, isDeviceOn: true)

        XCTAssertFalse(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithColorTemperature_ReturnsFalse() {
        let entityId = EntityId(placeId: "Living Room", name: "Light", characteristicsName: nil, characteristic: .colorTemperature)
        let item = EntityStorageItem(entityId: entityId, colorTemperature: 0.5)

        XCTAssertFalse(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithContactOpen_ReturnsFalse() {
        let entityId = EntityId(placeId: "Bedroom", name: "Door", characteristicsName: nil, characteristic: .contactSensor)
        let item = EntityStorageItem(entityId: entityId, isContactOpen: false)

        XCTAssertFalse(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithDoorLocked_ReturnsFalse() {
        let entityId = EntityId(placeId: "Front Door", name: "Lock", characteristicsName: nil, characteristic: .lock)
        let item = EntityStorageItem(entityId: entityId, isDoorLocked: true)

        XCTAssertFalse(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithStateOfCharge_ReturnsFalse() {
        let entityId = EntityId(placeId: "Living Room", name: "Sensor", characteristicsName: nil, characteristic: .batterySensor)
        let item = EntityStorageItem(entityId: entityId, stateOfCharge: 85)

        XCTAssertFalse(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithHeaterActive_ReturnsFalse() {
        let entityId = EntityId(placeId: "Living Room", name: "Heater", characteristicsName: nil, characteristic: .heating)
        let item = EntityStorageItem(entityId: entityId, isHeaterActive: true)

        XCTAssertFalse(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithRelativeHumidity_ReturnsFalse() {
        let entityId = EntityId(placeId: "Living Room", name: "Sensor", characteristicsName: nil, characteristic: .relativeHumiditySensor)
        let item = EntityStorageItem(entityId: entityId, relativeHumidity: 45.5)

        XCTAssertFalse(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithCarbonDioxide_ReturnsFalse() {
        let entityId = EntityId(placeId: "Living Room", name: "Sensor", characteristicsName: nil, characteristic: .carbonDioxideSensorId)
        let item = EntityStorageItem(entityId: entityId, carbonDioxideSensorId: 450)

        XCTAssertFalse(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithPMDensity_ReturnsFalse() {
        let entityId = EntityId(placeId: "Living Room", name: "Sensor", characteristicsName: nil, characteristic: .pmDensitySensor)
        let item = EntityStorageItem(entityId: entityId, pmDensity: 12.5)

        XCTAssertFalse(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithAirQuality_ReturnsFalse() {
        let entityId = EntityId(placeId: "Living Room", name: "Sensor", characteristicsName: nil, characteristic: .airQualitySensor)
        let item = EntityStorageItem(entityId: entityId, airQuality: 3)

        XCTAssertFalse(item.hasNoSensorData)
    }

    func testHasNoSensorData_WithValveOpen_ReturnsFalse() {
        let entityId = EntityId(placeId: "Garden", name: "Valve", characteristicsName: nil, characteristic: .valve)
        let item = EntityStorageItem(entityId: entityId, valveOpen: true)

        XCTAssertFalse(item.hasNoSensorData)
    }
}

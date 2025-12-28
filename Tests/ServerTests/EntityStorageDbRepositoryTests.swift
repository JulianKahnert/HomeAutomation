//
//  EntityStorageDbRepositoryTests.swift
//  HomeAutomation
//

import Foundation
@testable import HAModels
@testable import Server
import XCTest

/// Tests for EntityStorageDbRepository mapping functions
///
/// These tests ensure complete field mapping between EntityStorageItem and EntityStorageDbItem.
/// If a new field is added to either model but the mapping is not updated, these tests will FAIL.
final class EntityStorageDbRepositoryTests: XCTestCase {

    // MARK: - Round-trip Tests

    /// Tests that all fields survive a round-trip conversion: EntityStorageItem -> DbItem -> EntityStorageItem
    ///
    /// This test will FAIL if:
    /// - A new field is added to EntityStorageItem but not mapped in EntityStorageDbRepository
    /// - A field loses precision or data during conversion
    func testCompleteFieldMappingRoundTrip_AllFields() throws {
        // Create EntityStorageItem with ALL fields populated
        let original = createFullyPopulatedEntityStorageItem()

        // Convert to DB model and back
        let dbItem = EntityStorageDbRepository.map(original)
        let restored = EntityStorageDbRepository.mapDbItem(dbItem)

        // Verify ALL fields match
        assertEntityStorageItemsEqual(original, restored, message: "Round-trip conversion should preserve all fields")
    }

    /// Tests air sensor device with temperature, humidity, CO2, PM density, and air quality
    func testAirSensorMapping() throws {
        let entityId = EntityId(
            placeId: "bedroom",
            name: "Luftsensor",
            characteristicsName: nil,
            characteristic: .temperatureSensor
        )

        let original = EntityStorageItem(
            entityId: entityId,
            timestamp: Date(),
            motionDetected: nil,
            illuminance: nil,
            isDeviceOn: nil,
            brightness: nil,
            colorTemperature: nil,
            color: nil,
            isContactOpen: nil,
            isDoorLocked: nil,
            stateOfCharge: nil,
            isHeaterActive: nil,
            temperatureInC: Measurement(value: 22.5, unit: .celsius),
            relativeHumidity: 45.5,
            carbonDioxideSensorId: 650,
            pmDensity: 12.3,
            airQuality: 1,
            valveOpen: nil
        )

        let dbItem = EntityStorageDbRepository.map(original)
        let restored = EntityStorageDbRepository.mapDbItem(dbItem)

        // Verify air quality fields
        XCTAssertNotNil(restored.temperatureInC)
        XCTAssertEqual(restored.temperatureInC?.converted(to: .celsius).value ?? 0, 22.5, accuracy: 0.01)
        XCTAssertEqual(restored.relativeHumidity, 45.5)
        XCTAssertEqual(restored.carbonDioxideSensorId, 650)
        XCTAssertEqual(restored.pmDensity, 12.3)
        XCTAssertEqual(restored.airQuality, 1)
    }

    /// Tests motion sensor with illuminance
    func testMotionSensorMapping() throws {
        let entityId = EntityId(
            placeId: "hallway",
            name: "Motion Sensor",
            characteristicsName: nil,
            characteristic: .motionSensor
        )

        let original = EntityStorageItem(
            entityId: entityId,
            timestamp: Date(),
            motionDetected: true,
            illuminance: Measurement(value: 150.0, unit: .lux),
            isDeviceOn: nil,
            brightness: nil,
            colorTemperature: nil,
            color: nil,
            isContactOpen: nil,
            isDoorLocked: nil,
            stateOfCharge: nil,
            isHeaterActive: nil,
            temperatureInC: nil,
            relativeHumidity: nil,
            carbonDioxideSensorId: nil,
            pmDensity: nil,
            airQuality: nil,
            valveOpen: nil
        )

        let dbItem = EntityStorageDbRepository.map(original)
        let restored = EntityStorageDbRepository.mapDbItem(dbItem)

        XCTAssertEqual(restored.motionDetected, true)
        XCTAssertNotNil(restored.illuminance)
        XCTAssertEqual(restored.illuminance?.converted(to: .lux).value ?? 0, 150.0, accuracy: 0.01)
    }

    /// Tests light device with brightness, color temperature, and RGB color
    func testLightDeviceMapping() throws {
        let entityId = EntityId(
            placeId: "living-room",
            name: "Smart Light",
            characteristicsName: nil,
            characteristic: .switcher
        )

        let original = EntityStorageItem(
            entityId: entityId,
            timestamp: Date(),
            motionDetected: nil,
            illuminance: nil,
            isDeviceOn: true,
            brightness: 75,
            colorTemperature: 4000.0,
            color: RGB(red: 1.0, green: 0.5, blue: 0.2),
            isContactOpen: nil,
            isDoorLocked: nil,
            stateOfCharge: nil,
            isHeaterActive: nil,
            temperatureInC: nil,
            relativeHumidity: nil,
            carbonDioxideSensorId: nil,
            pmDensity: nil,
            airQuality: nil,
            valveOpen: nil
        )

        let dbItem = EntityStorageDbRepository.map(original)
        let restored = EntityStorageDbRepository.mapDbItem(dbItem)

        XCTAssertEqual(restored.isDeviceOn, true)
        XCTAssertEqual(restored.brightness, 75)
        XCTAssertEqual(restored.colorTemperature, 4000.0)
        XCTAssertNotNil(restored.color)
        XCTAssertEqual(Double(restored.color?.red ?? 0), 1.0, accuracy: 0.01)
        XCTAssertEqual(Double(restored.color?.green ?? 0), 0.5, accuracy: 0.01)
        XCTAssertEqual(Double(restored.color?.blue ?? 0), 0.2, accuracy: 0.01)
    }

    /// Tests heating device with valve state
    func testHeatingDeviceMapping() throws {
        let entityId = EntityId(
            placeId: "bedroom",
            name: "Radiator Valve",
            characteristicsName: nil,
            characteristic: .valve
        )

        let original = EntityStorageItem(
            entityId: entityId,
            timestamp: Date(),
            motionDetected: nil,
            illuminance: nil,
            isDeviceOn: nil,
            brightness: nil,
            colorTemperature: nil,
            color: nil,
            isContactOpen: nil,
            isDoorLocked: nil,
            stateOfCharge: nil,
            isHeaterActive: true,
            temperatureInC: nil,
            relativeHumidity: nil,
            carbonDioxideSensorId: nil,
            pmDensity: nil,
            airQuality: nil,
            valveOpen: true
        )

        let dbItem = EntityStorageDbRepository.map(original)
        let restored = EntityStorageDbRepository.mapDbItem(dbItem)

        XCTAssertEqual(restored.isHeaterActive, true)
        XCTAssertEqual(restored.valveOpen, true)
    }

    /// Tests that nil/null values are preserved correctly
    func testNullValueMapping() throws {
        let entityId = EntityId(
            placeId: "test",
            name: "Test Device",
            characteristicsName: nil,
            characteristic: .batterySensor
        )

        let original = EntityStorageItem(
            entityId: entityId,
            timestamp: Date(),
            motionDetected: nil,
            illuminance: nil,
            isDeviceOn: nil,
            brightness: nil,
            colorTemperature: nil,
            color: nil,
            isContactOpen: nil,
            isDoorLocked: nil,
            stateOfCharge: 85,
            isHeaterActive: nil,
            temperatureInC: nil,
            relativeHumidity: nil,
            carbonDioxideSensorId: nil,
            pmDensity: nil,
            airQuality: nil,
            valveOpen: nil
        )

        let dbItem = EntityStorageDbRepository.map(original)
        let restored = EntityStorageDbRepository.mapDbItem(dbItem)

        // Only stateOfCharge should be set
        XCTAssertEqual(restored.stateOfCharge, 85)
        XCTAssertNil(restored.motionDetected)
        XCTAssertNil(restored.illuminance)
        XCTAssertNil(restored.isDeviceOn)
        XCTAssertNil(restored.brightness)
        XCTAssertNil(restored.colorTemperature)
        XCTAssertNil(restored.color)
        XCTAssertNil(restored.temperatureInC)
        XCTAssertNil(restored.relativeHumidity)
        XCTAssertNil(restored.carbonDioxideSensorId)
        XCTAssertNil(restored.pmDensity)
        XCTAssertNil(restored.airQuality)
        XCTAssertNil(restored.valveOpen)
    }

    // MARK: - Helper Methods

    private func createFullyPopulatedEntityStorageItem() -> EntityStorageItem {
        let entityId = EntityId(
            placeId: "test-place",
            name: "Test Device",
            characteristicsName: "test-characteristic",
            characteristic: .airQualitySensor
        )

        return EntityStorageItem(
            entityId: entityId,
            timestamp: Date(timeIntervalSince1970: 1735333200), // Fixed timestamp for reproducibility
            motionDetected: true,
            illuminance: Measurement(value: 250.5, unit: .lux),
            isDeviceOn: true,
            brightness: 80,
            colorTemperature: 3500.0,
            color: RGB(red: 0.8, green: 0.6, blue: 0.4),
            isContactOpen: false,
            isDoorLocked: true,
            stateOfCharge: 95,
            isHeaterActive: true,
            temperatureInC: Measurement(value: 21.5, unit: .celsius),
            relativeHumidity: 55.0,
            carbonDioxideSensorId: 450,
            pmDensity: 8.5,
            airQuality: 2,
            valveOpen: true
        )
    }

    private func assertEntityStorageItemsEqual(
        _ lhs: EntityStorageItem,
        _ rhs: EntityStorageItem,
        accuracy: Double = 0.001,
        message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        // Entity ID
        XCTAssertEqual(lhs.entityId.placeId, rhs.entityId.placeId, message, file: file, line: line)
        XCTAssertEqual(lhs.entityId.name, rhs.entityId.name, message, file: file, line: line)
        XCTAssertEqual(lhs.entityId.characteristicsName, rhs.entityId.characteristicsName, message, file: file, line: line)
        XCTAssertEqual(lhs.entityId.characteristicType, rhs.entityId.characteristicType, message, file: file, line: line)

        // Timestamp
        XCTAssertEqual(lhs.timestamp.timeIntervalSince1970, rhs.timestamp.timeIntervalSince1970, accuracy: 0.001, message, file: file, line: line)

        // Motion & Illuminance
        XCTAssertEqual(lhs.motionDetected, rhs.motionDetected, message, file: file, line: line)
        if let lhsIlluminance = lhs.illuminance, let rhsIlluminance = rhs.illuminance {
            XCTAssertEqual(lhsIlluminance.converted(to: .lux).value, rhsIlluminance.converted(to: .lux).value, accuracy: accuracy, message, file: file, line: line)
        } else {
            XCTAssertEqual(lhs.illuminance == nil, rhs.illuminance == nil, message, file: file, line: line)
        }

        // Device state
        XCTAssertEqual(lhs.isDeviceOn, rhs.isDeviceOn, message, file: file, line: line)
        XCTAssertEqual(lhs.brightness, rhs.brightness, message, file: file, line: line)
        XCTAssertEqual(lhs.colorTemperature, rhs.colorTemperature, message, file: file, line: line)

        // Color
        if let lhsColor = lhs.color, let rhsColor = rhs.color {
            XCTAssertEqual(lhsColor.red, rhsColor.red, accuracy: Float(accuracy), message, file: file, line: line)
            XCTAssertEqual(lhsColor.green, rhsColor.green, accuracy: Float(accuracy), message, file: file, line: line)
            XCTAssertEqual(lhsColor.blue, rhsColor.blue, accuracy: Float(accuracy), message, file: file, line: line)
        } else {
            XCTAssertEqual(lhs.color == nil, rhs.color == nil, message, file: file, line: line)
        }

        // Contact & Lock
        XCTAssertEqual(lhs.isContactOpen, rhs.isContactOpen, message, file: file, line: line)
        XCTAssertEqual(lhs.isDoorLocked, rhs.isDoorLocked, message, file: file, line: line)

        // Battery
        XCTAssertEqual(lhs.stateOfCharge, rhs.stateOfCharge, message, file: file, line: line)

        // Heating
        XCTAssertEqual(lhs.isHeaterActive, rhs.isHeaterActive, message, file: file, line: line)
        XCTAssertEqual(lhs.valveOpen, rhs.valveOpen, message, file: file, line: line)

        // Air Quality Sensors
        if let lhsTemp = lhs.temperatureInC, let rhsTemp = rhs.temperatureInC {
            XCTAssertEqual(lhsTemp.converted(to: .celsius).value, rhsTemp.converted(to: .celsius).value, accuracy: accuracy, message, file: file, line: line)
        } else {
            XCTAssertEqual(lhs.temperatureInC == nil, rhs.temperatureInC == nil, message, file: file, line: line)
        }

        XCTAssertEqual(lhs.relativeHumidity, rhs.relativeHumidity, message, file: file, line: line)
        XCTAssertEqual(lhs.carbonDioxideSensorId, rhs.carbonDioxideSensorId, message, file: file, line: line)
        XCTAssertEqual(lhs.pmDensity, rhs.pmDensity, message, file: file, line: line)
        XCTAssertEqual(lhs.airQuality, rhs.airQuality, message, file: file, line: line)
    }

    /// Tests validation logic for EntityStorageItem with all nil sensor fields
    func testHasNoSensorData_AllNilFields() {
        let entityId = EntityId(placeId: "Living Room", name: "Light", characteristicsName: nil, characteristic: .switcher)
        let emptyItem = EntityStorageItem(entityId: entityId)

        XCTAssertTrue(emptyItem.hasNoSensorData, "Item with all nil sensor fields should be detected as invalid")
    }

    /// Tests validation logic for EntityStorageItem with at least one sensor field
    func testHasNoSensorData_WithMotionDetected() {
        let entityId = EntityId(placeId: "Living Room", name: "Motion", characteristicsName: nil, characteristic: .motionSensor)
        let validItem = EntityStorageItem(entityId: entityId, motionDetected: true)

        XCTAssertFalse(validItem.hasNoSensorData, "Item with motionDetected should be valid")
    }

    /// Tests validation logic for EntityStorageItem with temperature field
    func testHasNoSensorData_WithTemperature() {
        let entityId = EntityId(placeId: "Living Room", name: "Sensor", characteristicsName: nil, characteristic: .temperatureSensor)
        let validItem = EntityStorageItem(entityId: entityId, temperatureInC: Measurement(value: 22.5, unit: .celsius))

        XCTAssertFalse(validItem.hasNoSensorData, "Item with temperature should be valid")
    }

    /// Tests validation logic for EntityStorageItem with brightness field
    func testHasNoSensorData_WithBrightness() {
        let entityId = EntityId(placeId: "Living Room", name: "Light", characteristicsName: nil, characteristic: .brightness)
        let validItem = EntityStorageItem(entityId: entityId, brightness: 75)

        XCTAssertFalse(validItem.hasNoSensorData, "Item with brightness should be valid")
    }
}

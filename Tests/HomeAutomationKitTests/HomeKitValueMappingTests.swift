//
//  HomeKitValueMappingTests.swift
//  HomeAutomationKit
//

@testable import Adapter
import Foundation
import HAModels
import Testing
#if canImport(HomeKit)
import HomeKit
#endif

struct HomeKitValueMappingTests {
    private typealias Mapping = HomeKitValueMapping

    private func context(
        characteristic: String = "",
        minimum: Double? = nil,
        maximum: Double? = nil,
        saturation: Any? = nil,
        brightness: Any? = nil
    ) -> Mapping.Context {
        Mapping.Context(
            characteristicType: characteristic,
            minimumValue: minimum,
            maximumValue: maximum,
            saturation: saturation,
            brightness: brightness
        )
    }

    // MARK: motionSensor

    @Test func occupancyIsMotionWhenTheInt64ValueIsOne() {
        let ctx = context(characteristic: Mapping.occupancyDetectedCharacteristic)
        #expect(Mapping.value(.motionSensor, raw: Int64(1), context: ctx) == .bool(true))
        #expect(Mapping.value(.motionSensor, raw: Int64(0), context: ctx) == .bool(false))
        #expect(Mapping.value(.motionSensor, raw: nil, context: ctx) == .bool(false))
    }

    @Test func motionSensorReadsTheBool() {
        #expect(Mapping.value(.motionSensor, raw: true, context: context()) == .bool(true))
        #expect(Mapping.value(.motionSensor, raw: "x", context: context()) == nil)
    }

    // MARK: sensors

    @Test func illuminanceIsTheDoubleInLux() {
        #expect(Mapping.value(.lightSensor, raw: 12.5, context: context()) == .number(12.5))
        #expect(Mapping.value(.lightSensor, raw: Float(1), context: context()) == nil)
    }

    @Test func temperatureIsTheDoubleInCelsius() {
        #expect(Mapping.value(.temperatureSensor, raw: 21.5, context: context()) == .number(21.5))
        #expect(Mapping.value(.temperatureSensor, raw: nil, context: context()) == nil)
    }

    @Test func relativeHumidityIsTheDouble() {
        #expect(Mapping.value(.relativeHumiditySensor, raw: 48.0, context: context()) == .number(48))
        #expect(Mapping.value(.relativeHumiditySensor, raw: "48", context: context()) == nil)
    }

    @Test func carbonDioxideTruncatesTheFloat() {
        #expect(Mapping.value(.carbonDioxideSensorId, raw: Float(612.9), context: context()) == .number(612))
        #expect(Mapping.value(.carbonDioxideSensorId, raw: 612.0, context: context()) == nil)
    }

    @Test func pmDensityWidensTheFloat() {
        #expect(Mapping.value(.pmDensitySensor, raw: Float(7.5), context: context()) == .number(7.5))
        #expect(Mapping.value(.pmDensitySensor, raw: "7", context: context()) == nil)
    }

    @Test func airQualityIsTheInt() {
        #expect(Mapping.value(.airQualitySensor, raw: 3, context: context()) == .number(3))
        #expect(Mapping.value(.airQualitySensor, raw: "3", context: context()) == nil)
    }

    @Test func batteryLevelIsTheInt64() {
        #expect(Mapping.value(.batterySensor, raw: Int64(87), context: context()) == .number(87))
        #expect(Mapping.value(.batterySensor, raw: 87.5, context: context()) == nil)
    }

    // MARK: switches and states

    @Test func powerStateIsTheBool() {
        #expect(Mapping.value(.switcher, raw: true, context: context()) == .bool(true))
        #expect(Mapping.value(.switcher, raw: 1.5, context: context()) == nil)
    }

    @Test func contactIsOpenUnlessDetected() {
        #expect(Mapping.value(.contactSensor, raw: 0, context: context()) == .bool(false))
        #expect(Mapping.value(.contactSensor, raw: 1, context: context()) == .bool(true))
        #expect(Mapping.value(.contactSensor, raw: 2, context: context()) == nil)
    }

    @Test func lockIsSecuredOnlyForOne() {
        #expect(Mapping.value(.lock, raw: 1, context: context()) == .bool(true))
        #expect(Mapping.value(.lock, raw: 0, context: context()) == .bool(false))
        #expect(Mapping.value(.lock, raw: 2, context: context()) == .bool(false))
        #expect(Mapping.value(.lock, raw: 3, context: context()) == .bool(false))
        #expect(Mapping.value(.lock, raw: 4, context: context()) == nil)
    }

    @Test func heaterIsActiveForOneOnAHeaterCooler() {
        #expect(Mapping.value(.heating, raw: 1, context: context()) == .bool(true))
        #expect(Mapping.value(.heating, raw: 0, context: context()) == .bool(false))
        #expect(Mapping.value(.heating, raw: 2, context: context()) == nil)
    }

    @Test func valveIsOpenWhileInUse() {
        // HMCharacteristicValueInUseState: 0 not in use, 1 in use
        #expect(Mapping.value(.valve, raw: 1, context: context()) == .bool(true))
        #expect(Mapping.value(.valve, raw: 0, context: context()) == .bool(false))
        #expect(Mapping.value(.valve, raw: NSNumber(value: 1), context: context()) == .bool(true))
        #expect(Mapping.value(.valve, raw: 2, context: context()) == nil)
        #expect(Mapping.value(.valve, raw: "1", context: context()) == nil)
    }

    @Test func typesWithoutHomeKitSourceHaveNoValue() {
        for type in [CharacteristicsType.temperatureCalibration, .energyPrice, .deadline] {
            #expect(Mapping.value(type, raw: 1.0, context: context()) == nil)
        }
    }

    // MARK: light

    @Test func brightnessIsTheInt() {
        #expect(Mapping.value(.brightness, raw: 40, context: context()) == .number(40))
        #expect(Mapping.value(.brightness, raw: Float(40), context: context()) == nil)
    }

    @Test func colorTemperatureIsInvertedAndNormalized() {
        let ctx = context(minimum: 140, maximum: 500)
        #expect(Mapping.value(.colorTemperature, raw: 140, context: ctx) == .number(1))
        #expect(Mapping.value(.colorTemperature, raw: 500, context: ctx) == .number(0))
        #expect(Mapping.value(.colorTemperature, raw: 320, context: ctx) == .number(0.5))
    }

    @Test func colorTemperatureNeedsAValidRangeAndAnInt() {
        #expect(Mapping.value(.colorTemperature, raw: 300, context: context(minimum: 500, maximum: 140)) == nil)
        #expect(Mapping.value(.colorTemperature, raw: 300, context: context(minimum: 140, maximum: 140)) == nil)
        #expect(Mapping.value(.colorTemperature, raw: 300, context: context()) == nil)
        #expect(Mapping.value(.colorTemperature, raw: nil, context: context(minimum: 140, maximum: 500)) == nil)
    }

    @Test func colorIsHueWithSaturationAndBrightnessOfTheService() {
        let ctx = context(saturation: Float(100), brightness: Float(100))
        let expected = rgb(h: 120.0 / 360.0, s: 1, v: 1)
        #expect(Mapping.value(.color, raw: Float(120), context: ctx) == .text("\(expected.red) \(expected.green) \(expected.blue)"))
    }

    @Test func colorDefaultsToFullSaturationAndBrightness() {
        let full = rgb(h: 0.5, s: 1, v: 1)
        #expect(Mapping.value(.color, raw: Float(180), context: context()) == .text("\(full.red) \(full.green) \(full.blue)"))
        let half = rgb(h: 0.5, s: 0.5, v: 0.25)
        let ctx = context(saturation: Float(50), brightness: Float(25))
        #expect(Mapping.value(.color, raw: Float(180), context: ctx) == .text("\(half.red) \(half.green) \(half.blue)"))
        #expect(Mapping.value(.color, raw: 180, context: context()) == nil)
    }

    // MARK: heating

    @Test func targetTemperatureIsAnyNumber() {
        #expect(Mapping.value(.targetTemperature, raw: 21.5, context: context()) == .number(21.5))
        #expect(Mapping.value(.targetTemperature, raw: NSNumber(value: 19), context: context()) == .number(19))
        #expect(Mapping.value(.targetTemperature, raw: "19", context: context()) == nil)
    }

    @Test func thermostatModeKeepsTheRawValues() {
        let ctx = context(characteristic: HeatingControlCharacteristic.targetHeatingCoolingStateUUID)
        #expect(Mapping.value(.heatingMode, raw: 1, context: ctx) == .number(Double(HeatingMode.heat.rawValue)))
        #expect(Mapping.value(.heatingMode, raw: NSNumber(value: 0), context: ctx) == .number(Double(HeatingMode.off.rawValue)))
        #expect(Mapping.value(.heatingMode, raw: 9, context: ctx) == nil)
        #expect(Mapping.value(.heatingMode, raw: "1", context: ctx) == nil)
    }

    @Test func heaterCoolerModeRenumbersAutoHeatCool() {
        let ctx = context(characteristic: HeatingControlCharacteristic.targetHeaterCoolerStateUUID)
        #expect(Mapping.value(.heatingMode, raw: 0, context: ctx) == .number(Double(HeatingMode.auto.rawValue)))
        #expect(Mapping.value(.heatingMode, raw: 1, context: ctx) == .number(Double(HeatingMode.heat.rawValue)))
        #expect(Mapping.value(.heatingMode, raw: 2, context: ctx) == .number(Double(HeatingMode.cool.rawValue)))
        #expect(Mapping.value(.heatingMode, raw: 3, context: ctx) == nil)
    }

    @Test func eveValvePositionIsTheIntOfAnyNumber() {
        #expect(Mapping.value(.valvePosition, raw: NSNumber(value: 35.9), context: context()) == .number(35))
        #expect(Mapping.value(.valvePosition, raw: "35", context: context()) == nil)
    }

    // MARK: result fits the checked init

    @Test func everyMappedValueFitsTheCheckedInit() throws {
        let cases: [(CharacteristicsType, Any, Mapping.Context)] = [
            (.carbonDioxideSensorId, Float(500), context()),
            (.batterySensor, Int64(50), context()),
            (.brightness, 10, context()),
            (.heatingMode, 1, context(characteristic: HeatingControlCharacteristic.targetHeatingCoolingStateUUID)),
            (.valvePosition, NSNumber(value: 20), context()),
            (.color, Float(10), context())
        ]
        for (type, raw, ctx) in cases {
            let value = try #require(Mapping.value(type, raw: raw, context: ctx))
            let id = EntityId(placeId: "R", name: "N", characteristicsName: nil, characteristic: type)
            #expect(EntityStorageItem(entityId: id, value: value) != nil, "\(type)")
        }
    }

    #if canImport(HomeKit)
    @Test func uuidConstantsMatchHomeKit() {
        #expect(Mapping.occupancyDetectedCharacteristic == HMCharacteristicTypeOccupancyDetected)
    }

    /// What becomes an entity: a characteristic only on the service its kind belongs to.
    @Test(arguments: [
        (HMCharacteristicTypeBatteryLevel, HMServiceTypeBattery, true, CharacteristicsType.batterySensor),
        (HMCharacteristicTypeBatteryLevel, HMServiceTypeLightSensor, true, nil),
        (HMCharacteristicTypeContactState, HMServiceTypeContactSensor, true, .contactSensor),
        (HMCharacteristicTypeContactState, HMServiceTypeLockMechanism, true, nil),
        (HMCharacteristicTypeCurrentLightLevel, HMServiceTypeLightSensor, true, .lightSensor),
        (HMCharacteristicTypeCurrentLightLevel, HMServiceTypeMotionSensor, true, nil),
        (HMCharacteristicTypeMotionDetected, HMServiceTypeMotionSensor, true, .motionSensor),
        (HMCharacteristicTypeMotionDetected, HMServiceTypeOccupancySensor, true, nil),
        (HMCharacteristicTypeOccupancyDetected, HMServiceTypeOccupancySensor, true, .motionSensor),
        (HMCharacteristicTypeOccupancyDetected, HMServiceTypeMotionSensor, true, nil),
        (HMCharacteristicTypeTargetLockMechanismState, HMServiceTypeLockMechanism, true, .lock),
        (HMCharacteristicTypeTargetLockMechanismState, HMServiceTypeContactSensor, true, nil),
        (HMCharacteristicTypePowerState, HMServiceTypeOutlet, true, .switcher),
        (HMCharacteristicTypePowerState, HMServiceTypeOutlet, false, nil)
    ] as [(String, String, Bool, CharacteristicsType?)])
    func entitiesAreClassifiedByTheirService(characteristic: String, service: String, isBoolFormat: Bool, expected: CharacteristicsType?) throws {
        let homeKitCharacteristic = try #require(HomeKitCharacteristic(characteristicType: characteristic))
        #expect(homeKitCharacteristic.toCharacteristicsType(serviceType: service, isBoolFormat: isBoolFormat) == expected)
    }

    @Test func enumRawValuesMatchHomeKit() {
        #expect(HMCharacteristicValueContactState.detected.rawValue == 0)
        #expect(HMCharacteristicValueContactState.notDetected.rawValue == 1)
        #expect(HMCharacteristicValueLockMechanismState.secured.rawValue == 1)
        #expect(HMCharacteristicValueLockMechanismState.unknown.rawValue == 3)
        #expect(HMCharacteristicValueActivationState.active.rawValue == 1)
        #expect(HMCharacteristicValueActivationState.inactive.rawValue == 0)
    }
    #endif
}

//
//  HeatingControlCharacteristicTests.swift
//  HomeAutomationKit
//

@testable import Adapter
import HAModels
import Testing

struct HeatingControlCharacteristicTests {
    private typealias Control = HeatingControlCharacteristic

    @Test("Thermostat and HeaterCooler characteristics map to the same stored types", arguments: [
        (Control.targetTemperatureUUID, Control.thermostatServiceUUID, CharacteristicsType.targetTemperature),
        (Control.targetHeatingCoolingStateUUID, Control.thermostatServiceUUID, CharacteristicsType.heatingMode),
        (Control.heatingThresholdTemperatureUUID, Control.heaterCoolerServiceUUID, CharacteristicsType.targetTemperature),
        (Control.targetHeaterCoolerStateUUID, Control.heaterCoolerServiceUUID, CharacteristicsType.heatingMode)
    ])
    func mapsOnItsService(characteristicType: String, serviceType: String, expected: CharacteristicsType) {
        #expect(Control.characteristicsType(characteristicType: characteristicType, serviceType: serviceType) == expected)
    }

    @Test("A heating characteristic on the other or no service is not stored", arguments: [
        (Control.heatingThresholdTemperatureUUID, Control.thermostatServiceUUID as String?),
        (Control.targetHeaterCoolerStateUUID, Control.thermostatServiceUUID),
        (Control.targetTemperatureUUID, Control.heaterCoolerServiceUUID),
        (Control.targetHeatingCoolingStateUUID, Control.heaterCoolerServiceUUID),
        (Control.targetTemperatureUUID, nil)
    ])
    func ignoresOtherServices(characteristicType: String, serviceType: String?) {
        #expect(Control.characteristicsType(characteristicType: characteristicType, serviceType: serviceType) == nil)
    }

    @Test("UUIDs match case-insensitively")
    func matchesLowercaseUUIDs() {
        let type = Control.characteristicsType(characteristicType: Control.heatingThresholdTemperatureUUID.lowercased(),
                                          serviceType: Control.heaterCoolerServiceUUID.lowercased())
        #expect(type == .targetTemperature)
        #expect(Control.isHeatingControl(Control.targetHeaterCoolerStateUUID.lowercased()))
        #expect(Control.isHeatingService(Control.thermostatServiceUUID.lowercased()))
    }

    @Test("Other characteristics and services are not heating control")
    func rejectsOthers() {
        let currentTemperatureUUID = "00000011-0000-1000-8000-0026BB765291"
        let lightbulbServiceUUID = "00000043-0000-1000-8000-0026BB765291"
        #expect(!Control.isHeatingControl(currentTemperatureUUID))
        #expect(!Control.isHeatingControl(EveCharacteristic.valvePositionUUID))
        #expect(!Control.isHeatingService(lightbulbServiceUUID))
        #expect(!Control.isHeatingService(nil))
    }

    @Test("TargetHeatingCoolingState keeps HomeKit's numbering", arguments: [
        (0, HeatingMode.off), (1, .heat), (2, .cool), (3, .auto)
    ])
    func thermostatMode(rawValue: Int, expected: HeatingMode) {
        #expect(Control.heatingMode(rawValue: rawValue, characteristicType: Control.targetHeatingCoolingStateUUID) == expected)
    }

    @Test("TargetHeaterCoolerState numbers auto, heat, cool and has no off", arguments: [
        (0, HeatingMode.auto), (1, .heat), (2, .cool)
    ])
    func heaterCoolerMode(rawValue: Int, expected: HeatingMode) {
        #expect(Control.heatingMode(rawValue: rawValue, characteristicType: Control.targetHeaterCoolerStateUUID) == expected)
    }

    @Test("Unknown mode values and non-mode characteristics give nil")
    func unknownModes() {
        #expect(Control.heatingMode(rawValue: 3, characteristicType: Control.targetHeaterCoolerStateUUID) == nil)
        #expect(Control.heatingMode(rawValue: 4, characteristicType: Control.targetHeatingCoolingStateUUID) == nil)
        #expect(Control.heatingMode(rawValue: 1, characteristicType: Control.heatingThresholdTemperatureUUID) == nil)
    }

    @Test("Heating types are subscribed, so the adapter sends them to the server", arguments: [
        CharacteristicsType.heating, .targetTemperature, .heatingMode, .valvePosition, .temperatureCalibration
    ])
    func heatingTypesAreSubscribed(type: CharacteristicsType) {
        #expect(type.isSubscribed)
        #expect(type.isHeatingRelated)
    }

    @Test("Room temperature and humidity are subscribed, so standalone sensors reach the server", arguments: [
        CharacteristicsType.temperatureSensor, .relativeHumiditySensor
    ])
    func roomClimateTypesAreSubscribed(type: CharacteristicsType) {
        #expect(type.isSubscribed)
        #expect(!type.isHeatingRelated)
    }

    @Test("Sensors left out to keep HomeKit's subscription count down stay unsubscribed", arguments: [
        CharacteristicsType.valve, .lock, .pmDensitySensor, .airQualitySensor
    ])
    func otherTypesStayUnsubscribed(type: CharacteristicsType) {
        #expect(!type.isSubscribed)
        #expect(!type.isHeatingRelated)
    }
}

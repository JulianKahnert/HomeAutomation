//
//  GenericValueTests.swift
//  HomeAutomation
//

import Foundation
@testable import HAModels
import Testing

struct GenericValueTests {
    private let id = EntityId(placeId: "p", name: "e", characteristicsName: nil, characteristic: .switcher)

    private func id(_ type: CharacteristicsType) -> EntityId {
        EntityId(placeId: "p", name: "e", characteristicsName: nil, characteristic: type)
    }
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private var items: [EntityStorageItem] {
        [
            .init(entityId: id(.motionSensor), timestamp: date, motionDetected: true),
            .init(entityId: id(.lightSensor), timestamp: date, illuminance: .init(value: 312.5, unit: .lux)),
            .init(entityId: id(.switcher), timestamp: date, isDeviceOn: false),
            .init(entityId: id(.brightness), timestamp: date, brightness: 42),
            .init(entityId: id(.colorTemperature), timestamp: date, colorTemperature: 0.37),
            .init(entityId: id(.color), timestamp: date, color: RGB(red: 0.1, green: 0.25, blue: 0.9)),
            .init(entityId: id(.contactSensor), timestamp: date, isContactOpen: true),
            .init(entityId: id(.lock), timestamp: date, isDoorLocked: true),
            .init(entityId: id(.batterySensor), timestamp: date, stateOfCharge: 80),
            .init(entityId: id(.heating), timestamp: date, isHeaterActive: true),
            .init(entityId: id(.temperatureSensor), timestamp: date, temperatureInC: .init(value: 21.3, unit: .celsius)),
            .init(entityId: id(.relativeHumiditySensor), timestamp: date, relativeHumidity: 55.5),
            .init(entityId: id(.carbonDioxideSensorId), timestamp: date, carbonDioxideSensorId: 640),
            .init(entityId: id(.pmDensitySensor), timestamp: date, pmDensity: 7.25),
            .init(entityId: id(.airQualitySensor), timestamp: date, airQuality: 2),
            .init(entityId: id(.valve), timestamp: date, valveOpen: false),
            .init(entityId: id(.targetTemperature), timestamp: date, targetTemperatureInC: 19.5),
            .init(entityId: id(.heatingMode), timestamp: date, heatingMode: .auto),
            .init(entityId: id(.valvePosition), timestamp: date, valvePositionPercent: 30),
            .init(entityId: id(.temperatureCalibration), timestamp: date, temperatureCalibrationInC: -0.5),
            .init(entityId: id(.energyPrice), timestamp: date, energyPriceInEURPerKWh: 0.31),
            .init(entityId: id(.deadline), timestamp: date, deadline: .overdue(since: date))
        ]
    }

    @Test func itemsRoundTripThroughTheGenericForm() throws {
        #expect(Set(items.compactMap(\.kind)).count == CharacteristicsType.allCases.count)
        for item in items {
            let value = try #require(item.value)
            let back = try #require(EntityStorageItem(entityId: item.entityId, timestamp: date, value: value))
            #expect(back == item)
        }
    }

    @Test func energyPriceHasItsOwnKindWithEuroDescriptor() {
        let descriptor = ValueDescriptor.descriptor(for: .energyPrice)
        #expect(descriptor.shape == .number)
    }

    @Test func aValueThatDoesNotFitTheKindDoesNotConvert() {
        #expect(EntityStorageItem(entityId: id, value: .number(1)) == nil)
        #expect(EntityStorageItem(entityId: id(.heatingMode), value: .number(9)) == nil)
    }
}

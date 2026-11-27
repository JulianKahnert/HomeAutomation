//
//  GenericValueTests.swift
//  HomeAutomation
//

import Foundation
@testable import HAModels
import Testing

struct GenericValueTests {
    private let id = EntityId(placeId: "p", name: "e", characteristicsName: nil, characteristic: .switcher)
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(arguments: CharacteristicsType.allCases)
    func everyKindHasADescriptor(_ type: CharacteristicsType) {
        let descriptor = type.valueKind.descriptor
        #expect(descriptor?.kind == type.valueKind)
    }

    @Test func unknownKindHasNoDescriptor() {
        #expect(ValueKind(rawValue: "future").descriptor == nil)
    }

    private var items: [EntityStorageItem] {
        [
            .init(entityId: id, timestamp: date, motionDetected: true),
            .init(entityId: id, timestamp: date, illuminance: .init(value: 312.5, unit: .lux)),
            .init(entityId: id, timestamp: date, isDeviceOn: false),
            .init(entityId: id, timestamp: date, brightness: 42),
            .init(entityId: id, timestamp: date, colorTemperature: 0.37),
            .init(entityId: id, timestamp: date, color: RGB(red: 0.1, green: 0.25, blue: 0.9)),
            .init(entityId: id, timestamp: date, isContactOpen: true),
            .init(entityId: id, timestamp: date, isDoorLocked: true),
            .init(entityId: id, timestamp: date, stateOfCharge: 80),
            .init(entityId: id, timestamp: date, isHeaterActive: true),
            .init(entityId: id, timestamp: date, temperatureInC: .init(value: 21.3, unit: .celsius)),
            .init(entityId: id, timestamp: date, relativeHumidity: 55.5),
            .init(entityId: id, timestamp: date, carbonDioxideSensorId: 640),
            .init(entityId: id, timestamp: date, pmDensity: 7.25),
            .init(entityId: id, timestamp: date, airQuality: 2),
            .init(entityId: id, timestamp: date, valveOpen: false),
            .init(entityId: id, timestamp: date, targetTemperatureInC: 19.5),
            .init(entityId: id, timestamp: date, heatingMode: .auto),
            .init(entityId: id, timestamp: date, valvePositionPercent: 30),
            .init(entityId: id, timestamp: date, temperatureCalibrationInC: -0.5),
            .init(entityId: id, timestamp: date, energyPriceInEURPerKWh: 0.31)
        ]
    }

    @Test func itemsRoundTripThroughTheGenericForm() throws {
        #expect(Set(items.compactMap { $0.genericValue?.kind }).count == CharacteristicsType.allCases.count)
        for item in items {
            let generic = try #require(item.genericValue)
            let back = try #require(EntityStorageItem(entityId: item.entityId, timestamp: date, kind: generic.kind, value: generic.value))
            #expect(back == item)
        }
    }

    @Test func energyPriceHasItsOwnKindWithEuroDescriptor() {
        let descriptor = CharacteristicsType.energyPrice.valueKind.descriptor
        #expect(descriptor?.shape == .number)
        #expect(descriptor?.unit == "€/kWh")
    }

    @Test func mismatchingValueOrKindDoesNotConvert() {
        #expect(EntityStorageItem(entityId: id, kind: CharacteristicsType.switcher.valueKind, value: .number(1)) == nil)
        #expect(EntityStorageItem(entityId: id, kind: ValueKind(rawValue: "future"), value: .bool(true)) == nil)
        #expect(EntityStorageItem(entityId: id, kind: CharacteristicsType.heatingMode.valueKind, value: .number(9)) == nil)
    }
}

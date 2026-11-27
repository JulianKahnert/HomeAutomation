//
//  EntityStorageDbRepositoryTests.swift
//  HomeAutomation
//

import Foundation
@testable import HAModels
@testable import Server
import Testing

/// The mapping between a state and its narrow rows: a directory entry and one change with a number and a text.
@Suite("Narrow storage mapping")
struct EntityStorageMappingTests {
    static let samples: [(CharacteristicsType, Value)] = [
        (.motionSensor, .bool(true)), (.lightSensor, .number(250.5)), (.switcher, .bool(false)),
        (.brightness, .number(80)), (.colorTemperature, .number(3500)), (.color, .text("0.8 0.6 0.4")),
        (.contactSensor, .bool(true)), (.lock, .bool(false)), (.batterySensor, .number(95)),
        (.heating, .bool(true)), (.temperatureSensor, .number(21.5)), (.relativeHumiditySensor, .number(55)),
        (.carbonDioxideSensorId, .number(450)), (.pmDensitySensor, .number(8.5)), (.airQualitySensor, .number(2)),
        (.valve, .bool(false)), (.targetTemperature, .number(19.5)), (.heatingMode, .number(2)),
        (.valvePosition, .number(42)), (.temperatureCalibration, .number(-0.5)),
        (.energyPrice, .number(0.31)),
        (.deadline, .text("running 1800000000.0"))
    ]

    @Test("every value kind is covered by a sample")
    func samplesCoverAllKinds() {
        #expect(Set(Self.samples.map(\.0)) == Set(CharacteristicsType.allCases))
    }

    @Test("every value kind is stored and read back unchanged", arguments: samples)
    func roundTrip(type: CharacteristicsType, value: Value) throws {
        let id = EntityId(placeId: "Kitchen", name: "Device", characteristicsName: "Name", characteristic: type)
        let item = try #require(EntityStorageItem(entityId: id, timestamp: Date(timeIntervalSince1970: 1_735_333_200), value: value, origin: .server))
        let stored = try #require(item.value)
        let entity = EntityDbItem(placeId: id.placeId, serviceName: id.name, characteristicType: type.rawValue, characteristicsName: id.characteristicsName)
        let change = EntityChangeDbItem(entityId: UUID(), timestamp: item.timestamp, value: stored, shape: ValueDescriptor.descriptor(for: type).shape, origin: item.origin.rawValue)

        let restored = try #require(EntityStorageItem(entity: entity, change: change))

        #expect(restored == item)
        #expect(restored.origin == .server)
        #expect(restored.value == value)
    }

    @Test("a deadline is one row: the number for the end, the text for the case")
    func deadlineColumns() {
        let row = EntityChangeDbItem(entityId: UUID(), timestamp: Date(), value: .text("overdue 1800000000.0"), shape: .textWithNumber, origin: "server")
        let none = EntityChangeDbItem(entityId: UUID(), timestamp: Date(), value: .text("none"), shape: .textWithNumber, origin: "server")
        #expect(row.number == 1_800_000_000 && row.text == "overdue")
        #expect(none.number == nil && none.text == "none")
    }

    @Test("a bool is stored in the number column, a text in the text column")
    func columns() {
        let flag = EntityChangeDbItem(entityId: UUID(), timestamp: Date(), value: .bool(true), origin: "homekit")
        let text = EntityChangeDbItem(entityId: UUID(), timestamp: Date(), value: .text("1 2 3"), origin: "homekit")
        #expect(flag.number == 1 && flag.text == nil)
        #expect(text.number == nil && text.text == "1 2 3")
    }

    @Test("a heating mode this server does not know is read as an item without value")
    func unknownHeatingMode() throws {
        let entity = EntityDbItem(placeId: "Kitchen", serviceName: "Thermo", characteristicType: CharacteristicsType.heatingMode.rawValue, characteristicsName: nil)
        let change = EntityChangeDbItem(entityId: UUID(), timestamp: Date(), value: .number(9), origin: "homekit")

        let item = try #require(EntityStorageItem(entity: entity, change: change))

        #expect(item.heatingMode == nil)
    }

    @Test("an entity of an unknown characteristic type is skipped")
    func unknownType() {
        let entity = EntityDbItem(placeId: "Hall", serviceName: "Gone", characteristicType: "noLongerKnown", characteristicsName: nil)
        let change = EntityChangeDbItem(entityId: UUID(), timestamp: Date(), value: .bool(true), origin: "homekit")
        #expect(EntityStorageItem(entity: entity, change: change) == nil)
    }
}

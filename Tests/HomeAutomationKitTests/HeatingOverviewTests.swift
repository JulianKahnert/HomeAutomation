//
//  HeatingOverviewTests.swift
//  HomeAutomationKit
//

import Foundation
import HAModels
import Testing

@Suite("HeatingOverviewBuilder")
struct HeatingOverviewTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func id(_ place: String, _ name: String, _ type: CharacteristicsType = .temperatureSensor) -> EntityId {
        EntityId(placeId: place, name: name, characteristicsName: nil, characteristic: type)
    }

    private func room(_ place: String, name: String? = nil, sensor: EntityId? = nil) -> HeatingRoomSources {
        HeatingRoomSources(placeId: place, name: name ?? place,
                           radiators: [.init(name: "Thermo", temperatureId: id(place, "Thermo"), valvePositionId: id(place, "Thermo", .valvePosition))],
                           roomSensor: sensor, plan: nil)
    }

    private func temp(_ entity: EntityId, _ celsius: Double, minutesAgo: Double = 10) -> EntityStorageItem {
        EntityStorageItem(entityId: entity, timestamp: now.addingTimeInterval(-minutesAgo * 60), temperatureInC: .init(value: celsius, unit: .celsius))
    }

    private func plan(_ place: String, _ target: Double) -> HeatingWrite {
        HeatingWrite(timestamp: now.addingTimeInterval(-3 * 3_600), entityId: id(place, "Thermo", .heating), reason: .plan,
                     actionName: "setTargetTemperature", targetTemperatureInC: target, planTargetInC: target)
    }

    private func overview(_ rooms: [HeatingRoomSources], items: [EntityStorageItem], writes: [HeatingWrite]) async throws -> HeatingOverview {
        let detail = HeatingRoomDetailBuilder(storage: MockStorageRepository(items: items), writes: InMemoryHeatingWriteRepository(writes), now: { now })
        return try await HeatingOverviewBuilder(detail: detail).overview(for: rooms)
    }

    @Test("a room reports actual, plan target, delta and the source of the actual value")
    func deltaIsActualMinusPlan() async throws {
        let sensor = id("Bad", "Sensor")
        let result = try await overview([room("Bad", sensor: sensor)], items: [temp(sensor, 18.5)], writes: [plan("Bad", 21)])
        let bad = try #require(result.rooms.first)
        #expect(bad.ist == 18.5)
        #expect(bad.sollPlan == 21)
        #expect(bad.delta == -2.5)
        #expect(bad.istSource == .roomSensor("Sensor"))
    }

    @Test("without a sensor the source is the thermostats")
    func thermostatSource() async throws {
        let thermo = id("Küche", "Thermo")
        let result = try await overview([room("Küche")], items: [temp(thermo, 21)], writes: [plan("Küche", 21)])
        #expect(result.rooms.first?.istSource == .thermostats(["Thermo"]))
    }

    @Test("a room without an actual value has no delta")
    func noActual() async throws {
        let result = try await overview([room("Keller")], items: [], writes: [plan("Keller", 17)])
        let keller = try #require(result.rooms.first)
        #expect(keller.ist == nil)
        #expect(keller.delta == nil)
        #expect(keller.sollPlan == 17)
    }

    @Test("the comfort band edges are inside the band, beyond them the room is too cold or too warm")
    func comfortBandEdges() {
        func room(_ ist: Double) -> HeatingOverviewRoom {
            HeatingOverviewRoom(placeId: "R", name: "R", shortName: "R", ist: ist, sollPlan: 21, istSource: .thermostats([]))
        }
        #expect(room(20.5).comfort == .ok)
        #expect(room(21.5).comfort == .ok)
        #expect(room(20.4).comfort == .tooCold)
        #expect(room(21.6).comfort == .tooWarm)
        #expect(HeatingOverviewRoom(placeId: "R", name: "R", shortName: "R", ist: nil, sollPlan: 21, istSource: .thermostats([])).comfort == nil)
    }

    @Test("the short axis label drops the separator of the place name")
    func shortName() async throws {
        let result = try await overview([room("Bad - OG")], items: [], writes: [])
        #expect(result.rooms.first?.shortName == "Bad OG")
        #expect(result.rooms.first?.name == "Bad - OG")
    }
}

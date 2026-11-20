//
//  HeatingRoomDetailTests.swift
//  HomeAutomationKit
//

import Foundation
import HAModels
import Testing

@Suite("HeatingRoomDetailBuilder")
struct HeatingRoomDetailTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let thermoA = EntityId(placeId: "Bad", name: "Thermo A", characteristicsName: nil, characteristic: .temperatureSensor)
    private let thermoB = EntityId(placeId: "Bad", name: "Thermo B", characteristicsName: nil, characteristic: .temperatureSensor)
    private let valveA = EntityId(placeId: "Bad", name: "Thermo A", characteristicsName: nil, characteristic: .valvePosition)
    private let valveB = EntityId(placeId: "Bad", name: "Thermo B", characteristicsName: nil, characteristic: .valvePosition)
    private let sensor = EntityId(placeId: "Bad", name: "Sensor", characteristicsName: nil, characteristic: .temperatureSensor)

    private var sources: HeatingRoomSources {
        HeatingRoomSources(placeId: "Bad", name: "Bad",
                           radiators: [.init(name: "Thermo A", temperatureId: thermoA, valvePositionId: valveA),
                                       .init(name: "Thermo B", temperatureId: thermoB, valvePositionId: valveB)],
                           roomSensor: nil, plan: nil)
    }

    private func temp(_ id: EntityId, _ minutesAgo: Double, _ celsius: Double) -> EntityStorageItem {
        EntityStorageItem(entityId: id, timestamp: now.addingTimeInterval(-minutesAgo * 60), temperatureInC: .init(value: celsius, unit: .celsius))
    }

    private func valve(_ id: EntityId, _ minutesAgo: Double, _ percent: Int) -> EntityStorageItem {
        EntityStorageItem(entityId: id, timestamp: now.addingTimeInterval(-minutesAgo * 60), valvePositionPercent: percent)
    }

    private func builder(_ items: [EntityStorageItem], writes: [HeatingWrite] = []) -> HeatingRoomDetailBuilder {
        HeatingRoomDetailBuilder(storage: MockStorageRepository(items: items), writes: InMemoryHeatingWriteRepository(writes), now: { now })
    }

    @Test("the grid has 5 minute steps for 2 h and 24 h and 30 minute steps for 7 d")
    func gridSteps() async throws {
        let b = builder([temp(thermoA, 600, 20)])
        let twoHours = try await b.detail(for: sources, range: .twoHours)
        #expect(twoHours.samples.count == 25)
        #expect(twoHours.samples[1].date.timeIntervalSince(twoHours.samples[0].date) == 300)
        #expect(twoHours.samples.last?.date == now)
        let week = try await b.detail(for: sources, range: .week)
        #expect(week.samples[1].date.timeIntervalSince(week.samples[0].date) == 1800)
        #expect(week.samples.count == 7 * 48 + 1)
    }

    @Test("the room sensor wins over the thermostats")
    func sensorWins() async throws {
        var withSensor = sources
        withSensor.roomSensor = sensor
        let b = builder([temp(thermoA, 30, 25), temp(sensor, 30, 21)])
        let detail = try await b.detail(for: withSensor, range: .twoHours)
        #expect(detail.samples.last?.ist == 21)
        #expect(detail.istSource == .roomSensor("Sensor"))
    }

    @Test("without a sensor the actual value is the mean of the thermostats")
    func thermostatMean() async throws {
        let b = builder([temp(thermoA, 30, 20), temp(thermoB, 30, 22)])
        let detail = try await b.detail(for: sources, range: .twoHours)
        #expect(detail.samples.last?.ist == 21)
        #expect(detail.istSource == .thermostats(["Thermo A", "Thermo B"]))
    }

    @Test("each sample holds the last value at or before its grid point, and a state before the window carries in")
    func stepResampling() async throws {
        let b = builder([temp(thermoA, 200, 19), temp(thermoA, 60, 22)])
        let detail = try await b.detail(for: sources, range: .twoHours)
        #expect(detail.samples.first?.ist == 19)
        #expect(detail.samples.last?.ist == 22)
        let at = detail.samples.first { $0.date == now.addingTimeInterval(-60 * 60) }
        #expect(at?.ist == 22)
    }

    @Test("a reading older than the failure limit is a gap, and so is the time before the first reading")
    func gaps() async throws {
        let b = builder([temp(thermoA, 110, 20)])
        let detail = HeatingRoomDetailBuilder(storage: MockStorageRepository(items: [temp(thermoA, 110, 20)]),
                                              writes: InMemoryHeatingWriteRepository([]), now: { now }, sensorFailureLimit: 30 * 60)
        let result = try await detail.detail(for: sources, range: .twoHours)
        #expect(result.samples[0].ist == nil)
        #expect(result.samples[2].ist == 20)
        #expect(result.samples.last?.ist == nil)
        let late = try await b.detail(for: sources, range: .twoHours)
        #expect(late.samples.last?.ist == 20)
        let none = try await builder([temp(thermoA, 10, 20)]).detail(for: sources, range: .twoHours)
        #expect(none.samples[0].ist == nil)
    }

    @Test("valves are listed per radiator in the order of the room, null while silent")
    func valves() async throws {
        let b = builder([temp(thermoA, 30, 20), valve(valveA, 30, 40), valve(valveB, 10, 100)])
        let detail = try await b.detail(for: sources, range: .twoHours)
        #expect(detail.radiators == ["Thermo A", "Thermo B"])
        #expect(detail.samples.last?.valves == [40, 100])
        #expect(detail.samples.first?.valves == [nil, nil])
    }

    @Test("the plan target comes from the write log and falls back to the plan")
    func planTarget() async throws {
        let radiator = EntityId(placeId: "Bad", name: "Thermo A", characteristicsName: nil, characteristic: .targetTemperature)
        let write = HeatingWrite(timestamp: now.addingTimeInterval(-3_600), entityId: radiator, reason: .plan, actionName: "setTargetTemperature",
                                 targetTemperatureInC: 21, planTargetInC: 21)
        let detail = try await builder([temp(thermoA, 30, 20)], writes: [write]).detail(for: sources, range: .twoHours)
        #expect(detail.samples.last?.sollPlan == 21)
        #expect(detail.samples.first?.sollPlan == nil)
        #expect(detail.samples.last?.delta == -1)

        var planned = sources
        planned.plan = HeatingPlan([.init(weekdays: [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday], switchPoints: [.init(hour: 0, targetInC: 18)])])
        let fallback = try await builder([temp(thermoA, 30, 20)]).detail(for: planned, range: .twoHours)
        #expect(fallback.samples.first?.sollPlan == 18)
    }

    @Test("a write without a plan target does not change the plan history")
    func nonPlanWrites() async throws {
        let radiator = EntityId(placeId: "Bad", name: "Thermo A", characteristicsName: nil, characteristic: .heating)
        let plan = HeatingWrite(timestamp: now.addingTimeInterval(-3_600), entityId: radiator, reason: .plan, actionName: "setTargetTemperature", targetTemperatureInC: 21, planTargetInC: 21)
        let window = HeatingWrite(timestamp: now.addingTimeInterval(-600), entityId: radiator, reason: .window, actionName: "setHeating", isActive: false)
        let detail = try await builder([temp(thermoA, 30, 20)], writes: [plan, window]).detail(for: sources, range: .twoHours)
        #expect(detail.samples.last?.sollPlan == 21)
    }

    @Test("long histories are read completely")
    func pagination() async throws {
        let items = (0..<2_500).map { temp(thermoA, Double($0) * 0.05, 20 + Double($0 % 3)) }
        let detail = try await builder(items).detail(for: sources, range: .week)
        #expect(detail.samples.last?.ist != nil)
    }
}

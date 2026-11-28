//
//  HeatingRoomDetailTests.swift
//  HomeAutomationKit
//

import Foundation
import HAApplicationLayer
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

    private func builder(_ items: [EntityStorageItem], writes: [HeatingFixture] = []) -> HeatingRoomDetailBuilder {
        HeatingRoomDetailBuilder(storage: MockStorageRepository(items: items + writes.compactMap { $0.planTargetItem() }), journal: seededJournal(writes), now: { now })
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

    @Test("an unchanged value that still reports shows no gap, a silent sensor does")
    func reportingKeepsTheValue() async throws {
        let items = [temp(thermoA, 110, 20)]
        func detail(reportedMinutesAgo: Double?) async throws -> HeatingRoomDetail {
            let reportedAt = reportedMinutesAgo.map { now.addingTimeInterval(-$0 * 60) }
            return try await HeatingRoomDetailBuilder(storage: MockStorageRepository(items: items), journal: seededJournal(),
                                                      now: { now }, sensorFailureLimit: 30 * 60, lastReport: { _ in reportedAt })
                .detail(for: sources, range: .twoHours)
        }
        let reporting = try await detail(reportedMinutesAgo: 2)
        #expect(reporting.samples.last?.ist == 20)
        let silent = try await detail(reportedMinutesAgo: 90)
        #expect(silent.samples.last?.ist == nil)
        let unknown = try await detail(reportedMinutesAgo: nil)
        #expect(unknown.samples.last?.ist == nil)
    }

    @Test("a reading older than the failure limit is a gap, and so is the time before the first reading")
    func gaps() async throws {
        let b = builder([temp(thermoA, 110, 20)])
        let detail = HeatingRoomDetailBuilder(storage: MockStorageRepository(items: [temp(thermoA, 110, 20)]),
                                              journal: seededJournal(), now: { now }, sensorFailureLimit: 30 * 60)
        let result = try await detail.detail(for: sources, range: .twoHours)
        #expect(result.samples[0].ist == nil)
        #expect(result.samples[2].ist == 20)
        #expect(result.samples.last?.ist == nil)
        let late = try await b.detail(for: sources, range: .twoHours)
        #expect(late.samples.last?.ist == 20)
        let none = try await builder([temp(thermoA, 10, 20)]).detail(for: sources, range: .twoHours)
        #expect(none.samples[0].ist == nil)
    }

    @Test("lastIst is the newest actual reading, also from before the range; nil without any")
    func lastIst() async throws {
        let old = try await builder([temp(thermoA, 3 * 24 * 60, 20), temp(thermoB, 4 * 24 * 60, 21)]).detail(for: sources, range: .twoHours)
        #expect(old.lastIst == now.addingTimeInterval(-3 * 24 * 3_600))
        let recent = try await builder([temp(thermoA, 30, 20), temp(thermoB, 10, 22)]).detail(for: sources, range: .twoHours)
        #expect(recent.lastIst == now.addingTimeInterval(-10 * 60))
        var withSensor = sources
        withSensor.roomSensor = sensor
        let viaSensor = try await builder([temp(thermoA, 5, 20), temp(sensor, 50, 21)]).detail(for: withSensor, range: .twoHours)
        #expect(viaSensor.lastIst == now.addingTimeInterval(-50 * 60))
        let none = try await builder([]).detail(for: sources, range: .twoHours)
        #expect(none.lastIst == nil)
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
        let write = HeatingFixture(timestamp: now.addingTimeInterval(-3_600), action: .setTargetTemperature(radiator, celsius: 21), reason: .plan, planTargetInC: 21)
        let detail = try await builder([temp(thermoA, 30, 20)], writes: [write]).detail(for: sources, range: .twoHours)
        #expect(detail.samples.last?.sollPlan == 21)
        #expect(detail.samples.first?.sollPlan == nil)
        #expect(detail.samples.last?.delta == -1)

        var planned = sources
        planned.plan = HeatingPlan([.init(weekdays: [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday], switchPoints: [.init(hour: 0, targetInC: 18)])])
        let fallback = try await builder([temp(thermoA, 30, 20)]).detail(for: planned, range: .twoHours)
        #expect(fallback.samples.first?.sollPlan == 18)
    }

    @Test("the room detail never loads the whole write history, yet the plan target before the range still holds")
    func boundedWriteHistory() async throws {
        let radiator = EntityId(placeId: "Bad", name: "Thermo A", characteristicsName: nil, characteristic: .targetTemperature)
        let old = HeatingFixture(timestamp: now.addingTimeInterval(-30 * 86_400), action: .setTargetTemperature(radiator, celsius: 19), reason: .plan, planTargetInC: 19)
        let journal = StartSpyJournal(seededJournal([old]))
        let builder = HeatingRoomDetailBuilder(storage: MockStorageRepository(items: [temp(thermoA, 30, 20)] + [old.planTargetItem()].compactMap { $0 }), journal: journal, now: { now })

        let detail = try await builder.detail(for: sources, range: .twoHours)

        #expect(detail.samples.first?.sollPlan == 19)
        let starts = await journal.requestedStarts
        #expect(!starts.isEmpty)
        #expect(!starts.contains { $0 == nil })
    }

    @Test("a plan target reported while the room was off still moves the plan line")
    func unsentPlanWriteMovesPlan() async throws {
        let radiator = EntityId(placeId: "Bad", name: "Thermo A", characteristicsName: nil, characteristic: .targetTemperature)
        let off = HeatingFixture(timestamp: now.addingTimeInterval(-7_200), action: .setTargetTemperature(radiator, celsius: 21), reason: .plan, planTargetInC: 21)
        let unsent = EntityStorageItem(entityId: sources.planTargetId, timestamp: now.addingTimeInterval(-3_600), targetTemperatureInC: 17, origin: .server)

        let detail = try await builder([temp(thermoA, 30, 20), unsent], writes: [off]).detail(for: sources, range: .day)

        #expect(detail.samples.last?.sollPlan == 17)
        #expect(detail.samples.last?.delta == 3)
    }

    @Test("a write without a plan target does not change the plan history")
    func nonPlanWrites() async throws {
        let radiator = EntityId(placeId: "Bad", name: "Thermo A", characteristicsName: nil, characteristic: .heating)
        let plan = HeatingFixture(timestamp: now.addingTimeInterval(-3_600), action: .setTargetTemperature(radiator, celsius: 21), reason: .plan, planTargetInC: 21)
        let window = HeatingFixture(timestamp: now.addingTimeInterval(-600), action: .setHeating(radiator, active: false), reason: .window)
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

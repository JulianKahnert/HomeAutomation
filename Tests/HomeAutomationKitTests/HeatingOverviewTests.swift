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

    private func plan(_ place: String, _ target: Double) -> HeatingFixture {
        HeatingFixture(timestamp: now.addingTimeInterval(-3 * 3_600), entityId: id(place, "Thermo", .heating), reason: .plan,
                     actionName: "setTargetTemperature", targetTemperatureInC: target, planTargetInC: target)
    }

    private func overview(_ rooms: [HeatingRoomSources], items: [EntityStorageItem], writes: [HeatingFixture]) async throws -> HeatingOverview {
        let detail = HeatingRoomDetailBuilder(storage: MockStorageRepository(items: items + writes.compactMap { $0.planTargetItem() }), writes: InMemoryHeatingCommands(writes), now: { now })
        return try await HeatingOverviewBuilder(detail: detail).overview(for: rooms)
    }

    @Test("the rooms load at the same time and keep their order")
    func order() async throws {
        let names = (1...8).map { "Raum \($0)" }
        let items = names.enumerated().map { temp(id($1, "Thermo"), 18 + Double($0)) }

        let result = try await overview(names.map { room($0) }, items: items, writes: names.map { plan($0, 20) })

        #expect(result.rooms.map(\.placeId) == names)
        #expect(result.rooms.map(\.ist) == (0..<8).map { 18 + Double($0) })
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

    @Test("a configured short label wins over the derived one")
    func configuredShortName() async throws {
        var bad = room("Bad - OG", name: "Bad Obergeschoss")
        bad.shortName = "Bad"
        let result = try await overview([bad], items: [], writes: [])
        #expect(result.rooms.first?.name == "Bad Obergeschoss")
        #expect(result.rooms.first?.shortName == "Bad")
    }

    @Test("the delta is a field of the room, and travels through JSON")
    func explicitDelta() throws {
        let room = HeatingOverviewRoom(placeId: "R", name: "R", shortName: "R", ist: 19, sollPlan: 21, istSource: .thermostats([]))
        #expect(room.delta == -2)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(room)) as? [String: Any]
        #expect(json?["delta"] as? Double == -2)
        #expect(try JSONDecoder().decode(HeatingOverviewRoom.self, from: JSONEncoder().encode(room)) == room)
    }

    // MARK: - Week heatmap

    private var berlin: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }

    private func berlinDate(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 11) -> Date {
        berlin.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func heatmap(now: Date, sensor: EntityId, items: [EntityStorageItem], plan target: Double = 21) async throws -> [HeatingHeatmapCell] {
        let old = HeatingFixture(timestamp: now.addingTimeInterval(-8 * 86_400), entityId: id("Bad", "Thermo", .heating), reason: .plan, actionName: "setTargetTemperature", targetTemperatureInC: target, planTargetInC: target)
        let detail = HeatingRoomDetailBuilder(storage: MockStorageRepository(items: items + [old.planTargetItem()].compactMap { $0 }),
                                              writes: InMemoryHeatingCommands([old]),
                                              now: { now }, calendar: berlin)
        let result = try await HeatingOverviewBuilder(detail: detail, calendar: berlin).overview(for: [room("Bad", sensor: sensor)])
        return result.heatmap
    }

    private func reading(_ entity: EntityId, _ celsius: Double, at date: Date) -> EntityStorageItem {
        EntityStorageItem(entityId: entity, timestamp: date, temperatureInC: .init(value: celsius, unit: .celsius))
    }

    @Test("a heatmap cell is the mean delta of its six-hour segment on the local day")
    func segmentMean() async throws {
        let sensor = id("Bad", "Sensor")
        let now = berlinDate(18, 12)
        // 12-18 on the 17th: 19 degrees for three hours, then 20 degrees: mean delta -1.5 against 21.
        let items = [reading(sensor, 19, at: berlinDate(17, 0)), reading(sensor, 19, at: berlinDate(17, 12)), reading(sensor, 20, at: berlinDate(17, 15))]
        let cells = try await heatmap(now: now, sensor: sensor, items: items)
        let cell = try #require(cells.first { $0.placeId == "Bad" && $0.day == berlinDate(17, 0) && $0.segment == 2 })
        #expect(try #require(cell.delta) == -1.5)
        #expect(cells.first { $0.day == berlinDate(17, 0) && $0.segment == 0 }?.delta == -2)
    }

    @Test("a segment with more than half of its samples missing is null, exactly half is not")
    func moreThanHalfMissing() async throws {
        let sensor = id("Bad", "Sensor")
        let now = berlinDate(18, 12)
        // A reading at 12:00 holds for the 6 h failure limit: until 18:00. Segment 3 (18-24) is silent, segment 2 complete.
        let items = [reading(sensor, 21, at: berlinDate(17, 12))]
        let cells = try await heatmap(now: now, sensor: sensor, items: items)
        #expect(cells.first { $0.day == berlinDate(17, 0) && $0.segment == 2 }?.delta == 0)
        #expect(cells.first { $0.day == berlinDate(17, 0) && $0.segment == 3 }?.delta == nil)
        // Reading at 14:30: valid until 20:30; of the 12 samples of 18-24, 6 have a value: exactly half missing.
        let half = try await heatmap(now: now, sensor: sensor, items: [reading(sensor, 21, at: berlinDate(17, 14, 30))])
        #expect(half.first { $0.day == berlinDate(17, 0) && $0.segment == 3 }?.delta == 0)
        // Reading at 14:00: valid until 20:00, 5 of 12 samples have a value: more than half missing.
        let less = try await heatmap(now: now, sensor: sensor, items: [reading(sensor, 21, at: berlinDate(17, 14))])
        #expect(less.first { $0.day == berlinDate(17, 0) && $0.segment == 3 }?.delta == nil)
    }

    @Test("days and segments follow the local clock across the end of daylight saving time")
    func daylightSaving() async throws {
        let sensor = id("Bad", "Sensor")
        // 25 October 2026: clocks go back, the day has 25 hours; 0-6 holds 7 hours.
        let now = berlinDate(26, 12, month: 10)
        let items = [reading(sensor, 22, at: berlinDate(25, 0, month: 10))]
        let cells = try await heatmap(now: now, sensor: sensor, items: items)
        let day = berlinDate(25, 0, month: 10)
        #expect(cells.filter { $0.day == day }.map(\.segment).sorted() == [0, 1, 2, 3])
        #expect(cells.first { $0.day == day && $0.segment == 0 }?.delta == 1)
        #expect(Set(cells.map(\.day)).count == 7)
    }
}

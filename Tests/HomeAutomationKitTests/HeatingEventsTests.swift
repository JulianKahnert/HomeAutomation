//
//  HeatingEventsTests.swift
//  HomeAutomationKit
//

import Foundation
import HAModels
import Testing

@Suite("HeatingRoomDetailBuilder events")
struct HeatingEventsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let heating = EntityId(placeId: "Bad", name: "Thermo", characteristicsName: nil, characteristic: .heating)
    private let target = EntityId(placeId: "Bad", name: "Thermo", characteristicsName: nil, characteristic: .targetTemperature)
    private let temp = EntityId(placeId: "Bad", name: "Thermo", characteristicsName: nil, characteristic: .temperatureSensor)
    private let valve = EntityId(placeId: "Bad", name: "Thermo", characteristicsName: nil, characteristic: .valvePosition)
    private let window = EntityId(placeId: "Bad", name: "Fenster", characteristicsName: nil, characteristic: .contactSensor)
    private let fireplace = Fireplace.stateId

    private func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

    private func sources(contacts: [HeatingRoomSources.Contact] = []) -> HeatingRoomSources {
        HeatingRoomSources(placeId: "Bad", name: "Bad",
                           radiators: [.init(name: "Thermo", temperatureId: temp, valvePositionId: valve, targetTemperatureId: target)],
                           roomSensor: nil, plan: nil, contacts: contacts)
    }

    private var windowContact: HeatingRoomSources.Contact { .init(source: .window, name: "Fenster", entityId: window) }
    private var fireplaceContact: HeatingRoomSources.Contact { .init(source: .fireplace, name: "Kamin", entityId: fireplace) }

    private func write(_ reason: HeatingWriteReason, _ minutes: Double, target value: Double? = nil, active: Bool? = nil, plan: Double? = nil) -> HeatingWrite {
        HeatingWrite(timestamp: ago(minutes), entityId: value != nil ? target : heating, reason: reason,
                     actionName: value != nil ? "setTargetTemperature" : "setHeating", isActive: active,
                     targetTemperatureInC: value, planTargetInC: plan)
    }

    private func events(_ items: [EntityStorageItem] = [], writes: [HeatingWrite] = [], contacts: [HeatingRoomSources.Contact] = [],
                        range: HeatingRange = .day) async throws -> [HeatingEvent] {
        // the fireplace states are the server's own switches, the rest the stored entity states
        let switches = items.filter { $0.entityId == fireplace }.compactMap { item in item.isDeviceOn.map { FireplaceSwitch(timestamp: item.timestamp, isOn: $0) } }
        let builder = HeatingRoomDetailBuilder(storage: MockStorageRepository(items: items.filter { $0.entityId != fireplace }),
                                               writes: InMemoryHeatingCommands(writes),
                                               fireplace: InMemoryFireplaceRepository(switches),
                                               now: { now })
        return try await builder.detail(for: sources(contacts: contacts), range: range).events
    }

    @Test("a plan write becomes one plan event for all radiators written at once")
    func plan() async throws {
        let found = try await events(writes: [write(.plan, 60, active: true, plan: 21), write(.plan, 60, target: 21, plan: 21)])
        #expect(found.count == 1)
        #expect(found[0].source == .plan)
        #expect(found[0].start == ago(60))
        #expect(found[0].end == nil)
        #expect(found[0].title.contains("21"))
        #expect(!found[0].reason.isEmpty)
    }

    @Test("a plan target reported without sending it is no event and no manual change")
    func unsentPlanTarget() async throws {
        let planTarget = EntityStorageItem(entityId: sources().planTargetId, timestamp: ago(60), targetTemperatureInC: 17, origin: .server)
        let items = [EntityStorageItem(entityId: target, timestamp: ago(120), targetTemperatureInC: 21), planTarget]   // the radiator was not told

        #expect(try await events(items).isEmpty)
    }

    @Test("two events of one source in the same second do not share an id")
    func idsAreUnique() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = HeatingEvent(source: .observed, title: "Von Hand: 25,0 °C", reason: "Thermo A steht auf 25,0 °C", start: start)
        let second = HeatingEvent(source: .observed, title: "Von Hand: 25,0 °C", reason: "Thermo B steht auf 25,0 °C", start: start.addingTimeInterval(0.4))

        #expect(first.id != second.id)
        #expect(first.id == HeatingEvent(source: .observed, title: first.title, reason: first.reason, start: start).id)
    }

    @Test("a system write becomes a system event")
    func system() async throws {
        let found = try await events(writes: [write(.system, 30, target: 19, plan: 19)])
        #expect(found.map(\.source) == [.system])
    }

    @Test("a window open for a while is an event with a duration, from the contact's history")
    func windowDuration() async throws {
        let items = [EntityStorageItem(entityId: window, timestamp: ago(90), isContactOpen: true),
                     EntityStorageItem(entityId: window, timestamp: ago(40), isContactOpen: false)]
        let found = try await events(items, writes: [write(.window, 85, active: false), write(.window, 40, target: 21, plan: 21)], contacts: [windowContact])
        #expect(found.count == 1)
        #expect(found[0].source == .window)
        #expect(found[0].start == ago(90))
        #expect(found[0].end == ago(40))
    }

    @Test("a window opened shortly, without a write, is no event")
    func shortWindow() async throws {
        let items = [EntityStorageItem(entityId: window, timestamp: ago(90), isContactOpen: true),
                     EntityStorageItem(entityId: window, timestamp: ago(89), isContactOpen: false)]
        #expect(try await events(items, contacts: [windowContact]).isEmpty)
    }

    @Test("a window still open has no end")
    func windowOpen() async throws {
        let items = [EntityStorageItem(entityId: window, timestamp: ago(20), isContactOpen: true)]
        let found = try await events(items, writes: [write(.window, 15, active: false)], contacts: [windowContact])
        #expect(found.first?.end == nil)
    }

    @Test("the fireplace is an event with a duration and its own reason")
    func fireplaceEvent() async throws {
        let items = [EntityStorageItem(entityId: fireplace, timestamp: ago(200), isDeviceOn: true),
                     EntityStorageItem(entityId: fireplace, timestamp: ago(80), isDeviceOn: false)]
        let found = try await events(items, writes: [write(.fireplace, 200, active: false)], contacts: [fireplaceContact])
        #expect(found.map(\.source) == [.fireplace])
        #expect(found[0].start == ago(200))
        #expect(found[0].end == ago(80))
    }

    @Test("a fireplace that ran its maximum duration says the timeout ended it")
    func fireplaceTimeout() async throws {
        let items = [EntityStorageItem(entityId: fireplace, timestamp: ago(120 + Fireplace.maxDuration / 60), isDeviceOn: true),
                     EntityStorageItem(entityId: fireplace, timestamp: ago(120), isDeviceOn: false)]
        let found = try await events(items, contacts: [fireplaceContact], range: .week)
        #expect(found.first?.reason.contains("Zeitablauf") == true)
    }

    @Test("without contacts, window and fireplace writes still give pins")
    func writesWithoutContacts() async throws {
        let found = try await events(writes: [write(.window, 50, active: false), write(.fireplace, 20, active: false)])
        #expect(found.map(\.source) == [.window, .fireplace])
    }

    @Test("a target that differs from the value the server wrote last is an observed event")
    func observed() async throws {
        let items = [EntityStorageItem(entityId: target, timestamp: ago(59), targetTemperatureInC: 21),
                     EntityStorageItem(entityId: target, timestamp: ago(30), targetTemperatureInC: 24)]
        let found = try await events(items, writes: [write(.plan, 60, target: 21, plan: 21)])
        let observed = found.filter { $0.source == .observed }
        #expect(observed.count == 1)
        #expect(observed[0].start == ago(30))
        #expect(observed[0].reason.contains("24"))
    }

    @Test("the echo of the server's own write is not observed, and neither is a change before any write")
    func notObserved() async throws {
        let echo = [EntityStorageItem(entityId: target, timestamp: ago(60).addingTimeInterval(2), targetTemperatureInC: 21)]
        #expect(try await events(echo, writes: [write(.plan, 60, target: 21, plan: 21)]).allSatisfy { $0.source != .observed })
        let before = [EntityStorageItem(entityId: target, timestamp: ago(30), targetTemperatureInC: 24)]
        #expect(try await events(before).isEmpty)
    }

    @Test("a new server write ends the observation: the same manual value is reported once")
    func observedOnce() async throws {
        let items = [EntityStorageItem(entityId: target, timestamp: ago(30), targetTemperatureInC: 24),
                     EntityStorageItem(entityId: target, timestamp: ago(20), targetTemperatureInC: 24)]
        let found = try await events(items, writes: [write(.plan, 60, target: 21, plan: 21)])
        #expect(found.filter { $0.source == .observed }.count == 1)
    }

    @Test("an event that began before the range keeps its real start and its pin sits at the range start")
    func clipping() async throws {
        let items = [EntityStorageItem(entityId: fireplace, timestamp: ago(300), isDeviceOn: true),
                     EntityStorageItem(entityId: fireplace, timestamp: ago(60), isDeviceOn: false)]
        let found = try await events(items, contacts: [fireplaceContact], range: .twoHours)
        #expect(found.count == 1)
        #expect(found[0].start == ago(300))
        #expect(found[0].pin == ago(120))
        #expect(found[0].end == ago(60))
    }

    @Test("events entirely outside the range are dropped, those inside pin at their start")
    func outside() async throws {
        let found = try await events(writes: [write(.plan, 500, target: 21, plan: 21), write(.plan, 30, target: 19, plan: 19)], range: .twoHours)
        #expect(found.count == 1)
        #expect(found[0].pin == found[0].start)
    }

    @Test("events are sorted by pin position")
    func sorted() async throws {
        let found = try await events(writes: [write(.plan, 10, target: 19, plan: 19), write(.system, 50, target: 20)])
        #expect(found.map(\.source) == [.system, .plan])
    }

    @Test("the writes the events look at reach back at most a day before the range, however old the state before it is")
    func writeLookback() async throws {
        let writes = WriteQueryLog()
        let items = [EntityStorageItem(entityId: window, timestamp: ago(60 * 24 * 90), isContactOpen: false)]   // a quiet contact, last changed months ago
        let builder = HeatingRoomDetailBuilder(storage: MockStorageRepository(items: items), writes: writes, now: { now })

        _ = try await builder.detail(for: sources(contacts: [windowContact]), range: .day)

        #expect(await writes.startDates == [now.addingTimeInterval(-HeatingRange.day.duration - 24 * 3_600)])
    }

    @Test("without events the detail skips the contacts and loads the writes of the range only")
    func withoutEvents() async throws {
        let writes = WriteQueryLog()
        let items = [EntityStorageItem(entityId: window, timestamp: ago(200), isContactOpen: true)]
        let builder = HeatingRoomDetailBuilder(storage: MockStorageRepository(items: items), writes: writes, now: { now })

        let detail = try await builder.detail(for: sources(contacts: [windowContact]), range: .day, includeEvents: false)

        #expect(detail.events.isEmpty)
        #expect(await writes.startDates == [now.addingTimeInterval(-HeatingRange.day.duration)])
    }
}

/// Answers no writes and remembers from when each query asked.
private actor WriteQueryLog: HeatingCommandSource {
    private(set) var startDates: [Date?] = []

    func writes(placeId: String, startDate: Date?, endDate: Date?) async -> [HeatingWrite] {
        startDates.append(startDate)
        return []
    }
}

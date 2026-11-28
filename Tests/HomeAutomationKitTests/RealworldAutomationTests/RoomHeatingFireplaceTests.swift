//
//  RoomHeatingFireplaceTests.swift
//  HomeAutomationKitTests
//

import Foundation
@testable import HAImplementations
import HAModels
import Testing

@Suite("RoomHeating follows the fireplace")
@HomeManagerActor
struct RoomHeatingFireplaceTests {
    private let plan = HeatingPlan([
        .init(weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday],
              switchPoints: [SwitchPoint(hour: 6, targetInC: 21), SwitchPoint(hour: 22, targetInC: 17)])
    ])
    private let left = Radiator(query: .init(placeId: "Cellar", name: "Left"))
    private let window = WindowContactSensor(query: .init(placeId: "Cellar", name: "Window"))
    private let homeManager = MockHomeAdapter()
    private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)   // not at a switch point, whatever the zone is

    private func room() -> RoomHeating {
        RoomHeating("heating-cellar", placeId: "Cellar", radiators: [left], contacts: [.window(window), .fireplace()],
                    configuration: HeatingConfiguration(standardPlan: plan))
    }

    private func setFireplace(on: Bool, at date: Date) {
        homeManager.fireplaceSwitches.append(FireplaceSwitch(timestamp: date, isOn: on))
    }

    private func setWindow(open: Bool, at date: Date) {
        homeManager.storageItems.append(EntityStorageItem(entityId: window.contactSensorId, timestamp: date, isContactOpen: open))
    }

    /// The server switched the radiator off for `reason` at `date`.
    private func seedOff(reason: HeatingWriteReason, at date: Date) {
        homeManager.heatingWrites.append(seededWrite(timestamp: date, action: .setHeating(left.heatingId, active: false), reason: reason))
    }

    private func change(_ id: EntityId) -> HomeEvent {
        .change(entity: homeManager.storageItems.last { $0.entityId == id }!)
    }

    /// The change event the server sends after the last switch of the fireplace.
    private func fireplaceEvent() -> HomeEvent {
        .change(entity: homeManager.storageItems.last { $0.entityId == Fireplace.stateId }!)
    }

    private func targets() -> [Double] {
        homeManager.performedActions.compactMap {
            if case .setTargetTemperature(_, let celsius) = $0.action { return celsius }
            return nil
        }
    }

    @Test("The fireplace on switches the radiators off at once, with reason fireplace")
    func fireplaceOnSwitchesOff() async throws {
        setFireplace(on: true, at: noon)

        #expect(try await room().shouldTrigger(with: fireplaceEvent(), using: homeManager))
        try await room().execute(using: homeManager, now: noon, sleep: { _ in Issue.record("the fireplace has no delay") })

        #expect(homeManager.performedActions.map(\.action) == [.setHeating(left.heatingId, active: false)])
        #expect(homeManager.performedActions.allSatisfy { $0.heating == .fireplace })
    }

    @Test("The fireplace going off returns the room to its plan at once, with reason fireplace")
    func fireplaceOffReturnsToPlan() async throws {
        setFireplace(on: true, at: noon)
        seedOff(reason: .fireplace, at: noon)
        let end = noon.addingTimeInterval(3600)
        setFireplace(on: false, at: end)

        #expect(try await room().shouldTrigger(with: fireplaceEvent(), using: homeManager))
        try await room().execute(using: homeManager, now: end, sleep: { _ in })

        let target = plan.planTarget(at: end)!
        #expect(targets() == [target])
        #expect(homeManager.performedActions.allSatisfy { $0.heating == .fireplace })
    }

    @Test("Window and fireplace both on: the window closing keeps the room off")
    func windowEndsFireplaceKeeps() async throws {
        setWindow(open: true, at: noon)
        setFireplace(on: true, at: noon.addingTimeInterval(30))
        let closed = noon.addingTimeInterval(600)
        setWindow(open: false, at: closed)

        try await room().execute(using: homeManager, now: closed, sleep: { _ in })

        #expect(targets().isEmpty)
        #expect(homeManager.performedActions.map(\.action) == [.setHeating(left.heatingId, active: false)])
    }

    @Test("Window and fireplace both on: the fireplace going off keeps the room off while the window is open")
    func fireplaceEndsWindowKeeps() async throws {
        setWindow(open: true, at: noon)
        setFireplace(on: true, at: noon.addingTimeInterval(30))
        let end = noon.addingTimeInterval(600)
        setFireplace(on: false, at: end)

        try await room().execute(using: homeManager, now: end, sleep: { _ in })

        #expect(targets().isEmpty)
        #expect(homeManager.performedActions.map(\.action) == [.setHeating(left.heatingId, active: false)])
    }

    @Test("Window and fireplace both on, then both end: the room returns to its plan")
    func bothEnd() async throws {
        setWindow(open: true, at: noon)
        setFireplace(on: true, at: noon.addingTimeInterval(30))
        setFireplace(on: false, at: noon.addingTimeInterval(600))
        seedOff(reason: .window, at: noon.addingTimeInterval(10))
        let last = noon.addingTimeInterval(900)
        setWindow(open: false, at: last)

        #expect(try await room().shouldTrigger(with: change(window.contactSensorId), using: homeManager))
        try await room().execute(using: homeManager, now: last, sleep: { _ in })

        #expect(targets() == [plan.planTarget(at: last)!])
    }

    @Test("The fireplace going off returns the room to its plan although its own off write was a skipped duplicate")
    func fireplaceEndsAfterDuplicateOff() async throws {
        setWindow(open: true, at: noon)
        seedOff(reason: .window, at: noon.addingTimeInterval(10))
        setFireplace(on: true, at: noon.addingTimeInterval(30))
        // the fireplace now holds the radiator; its setHeating(false) was a duplicate, so nothing was recorded with reason fireplace
        setWindow(open: false, at: noon.addingTimeInterval(60))
        let end = noon.addingTimeInterval(3600)
        setFireplace(on: false, at: end)

        #expect(try await room().shouldTrigger(with: fireplaceEvent(), using: homeManager))
        try await room().execute(using: homeManager, now: end, sleep: { _ in })

        let target = plan.planTarget(at: end)!
        #expect(targets() == [target])
        #expect(homeManager.performedActions.allSatisfy { $0.heating == .fireplace })
    }

    @Test("An unreachable fireplace switch counts as off: the plan keeps running")
    func unreachableIsOff() async throws {
        // no state of the switch at all
        #expect(try await !room().shouldTrigger(with: .serverStarted, using: homeManager))
        try await room().execute(using: homeManager, now: noon, isDeploy: true, sleep: { _ in })

        #expect(homeManager.performedActions.allSatisfy { if case .setTargetTemperature = $0.action { true } else { $0.action == .setHeating(left.heatingId, active: true) } })
        #expect(targets() == [plan.planTarget(at: noon)!])
    }

    @Test("A degraded HomeKit does not end the fireplace: the server's own state counts")
    func degradedHomeKitKeepsTheState() async throws {
        setFireplace(on: true, at: noon.addingTimeInterval(-3600))
        homeManager.health = .degraded(reason: "homed dropped the adapter")

        #expect(try await Fireplace.state(with: homeManager).isOn)
        #expect(try await room().shouldTrigger(with: .serverStarted, using: homeManager))
    }

    @Test("A restart with the fireplace on switches the room off by itself, without a plan write")
    func restartWithFireplaceOn() async throws {
        setFireplace(on: true, at: noon.addingTimeInterval(-3600))

        #expect(try await room().shouldTrigger(with: .serverStarted, using: homeManager))
        try await room().execute(using: homeManager, now: noon, sleep: { _ in })

        #expect(homeManager.performedActions.map(\.action) == [.setHeating(left.heatingId, active: false)])
        #expect(targets().isEmpty)
    }

    @Test("A room that does not list the fireplace ignores it")
    func otherRoomIgnoresFireplace() async throws {
        let plain = RoomHeating("heating-plain", placeId: "Cellar", radiators: [left], contacts: [.window(window)], configuration: HeatingConfiguration(standardPlan: plan))
        setFireplace(on: true, at: noon)

        #expect(try await !plain.shouldTrigger(with: .change(entity: EntityStorageItem(entityId: Fireplace.stateId, timestamp: noon, isDeviceOn: true)), using: homeManager))
        #expect(try await !plain.shouldTrigger(with: .serverStarted, using: homeManager))
    }

    @Test("The fireplace contact survives the configuration JSON")
    func codable() throws {
        let decoded = try JSONDecoder().decode(AnyAutomation.self, from: JSONEncoder().encode(AnyAutomation.create(from: room())))

        let decodedRoom = try #require(decoded.automation as? RoomHeating)
        #expect(decodedRoom.contacts.map(\.source) == [.window, .fireplace])
    }

    @Test("The fireplace switched off without the server having acted writes nothing")
    func fireplaceOffWithoutOffState() async throws {
        setFireplace(on: true, at: noon)
        setFireplace(on: false, at: noon.addingTimeInterval(60))

        #expect(try await !room().shouldTrigger(with: fireplaceEvent(), using: homeManager))
    }

    @Test("A change of the fireplace entity switches the rooms that list it off at once")
    func fireplaceChangeTriggers() async throws {
        setFireplace(on: true, at: noon)

        #expect(try await room().shouldTrigger(with: fireplaceEvent(), using: homeManager))
    }
}

@Suite("RoomHeating follows the fireplace with some radiators")
@HomeManagerActor
struct RoomHeatingFireplaceRadiatorsTests {
    private let plan = HeatingPlan([
        .init(weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday],
              switchPoints: [SwitchPoint(hour: 6, targetInC: 21), SwitchPoint(hour: 22, targetInC: 17)])
    ])
    private let fireside = Radiator(query: .init(placeId: "Cellar", name: "Fireside"))
    private let door = Radiator(query: .init(placeId: "Cellar", name: "Door"))
    private let window = WindowContactSensor(query: .init(placeId: "Cellar", name: "Window"))
    private let homeManager = MockHomeAdapter()
    private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)   // not at a switch point, whatever the zone is

    private func room() -> RoomHeating {
        RoomHeating("heating-cellar", placeId: "Cellar", radiators: [fireside, door], contacts: [.window(window), .fireplace(radiators: [fireside])],
                    configuration: HeatingConfiguration(standardPlan: plan))
    }

    private func setFireplace(on: Bool, at date: Date) {
        homeManager.fireplaceSwitches.append(FireplaceSwitch(timestamp: date, isOn: on))
    }

    private func setWindow(open: Bool, at date: Date) {
        homeManager.storageItems.append(EntityStorageItem(entityId: window.contactSensorId, timestamp: date, isContactOpen: open))
    }

    private func seedOff(_ radiator: Radiator, reason: HeatingWriteReason, at date: Date) {
        homeManager.heatingWrites.append(seededWrite(timestamp: date, action: .setHeating(radiator.heatingId, active: false), reason: reason))
    }

    @Test("The fireplace on switches only the listed radiators off")
    func onlyListedRadiatorsGoOff() async throws {
        setFireplace(on: true, at: noon)

        try await room().execute(using: homeManager, now: noon, sleep: { _ in })

        #expect(homeManager.performedActions.map(\.action) == [.setHeating(fireside.heatingId, active: false)])
        #expect(homeManager.performedActions.allSatisfy { $0.heating == .fireplace })
    }

    @Test("The fireplace going off returns only the listed radiators to the plan")
    func onlyListedRadiatorsReturn() async throws {
        setFireplace(on: true, at: noon)
        seedOff(fireside, reason: .fireplace, at: noon)
        let end = noon.addingTimeInterval(3600)
        setFireplace(on: false, at: end)
        let target = plan.planTarget(at: end)!

        try await room().execute(using: homeManager, now: end, sleep: { _ in })

        #expect(homeManager.performedActions.map(\.action) == [.setHeating(fireside.heatingId, active: true), .setTargetTemperature(fireside.targetTemperatureId, celsius: target)])
    }

    @Test("An open window switches every radiator off, the fireplace only its own")
    func windowPrecedesPerRadiator() async throws {
        setFireplace(on: true, at: noon)
        setWindow(open: true, at: noon.addingTimeInterval(-60))

        try await room().execute(using: homeManager, now: noon, sleep: { _ in })

        #expect(homeManager.performedActions.map(\.action) == [.setHeating(fireside.heatingId, active: false), .setHeating(door.heatingId, active: false)])
        #expect(homeManager.performedActions.map { $0.heating } == [.window, .window])
    }

    @Test("The window closing while the fireplace burns returns only the radiators the fireplace does not hold")
    func windowEndsFireplaceHoldsItsRadiators() async throws {
        setFireplace(on: true, at: noon)
        setWindow(open: true, at: noon.addingTimeInterval(-60))
        seedOff(fireside, reason: .window, at: noon.addingTimeInterval(-50))
        seedOff(door, reason: .window, at: noon.addingTimeInterval(-50))
        let closed = noon.addingTimeInterval(600)
        setWindow(open: false, at: closed)
        let target = plan.planTarget(at: closed)!

        try await room().execute(using: homeManager, now: closed, sleep: { _ in })

        #expect(homeManager.performedActions.map(\.action) == [.setHeating(fireside.heatingId, active: false),
                                                              .setHeating(door.heatingId, active: true), .setTargetTemperature(door.targetTemperatureId, celsius: target)])
    }

    @Test("A switch point while the fireplace burns writes the plan to the other radiators and reports the plan target")
    func switchPointMixed() async throws {
        let switchPoint = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 22)) ?? .distantPast
        setFireplace(on: true, at: switchPoint.addingTimeInterval(-3600))

        try await room().execute(using: homeManager, now: switchPoint, sleep: { _ in })

        #expect(homeManager.performedActions.map(\.action) == [.setHeating(fireside.heatingId, active: false),
                                                              .setHeating(door.heatingId, active: true), .setTargetTemperature(door.targetTemperatureId, celsius: 17)])
        #expect(homeManager.storageItems.filter { $0.entityId == HeatingRoomSources.planTargetId(placeId: "Cellar") }.map(\.targetTemperatureInC) == [17])
    }

    @Test("A contact without radiators switches all of them off, and the list survives the configuration JSON")
    func codable() throws {
        let all = RoomHeating("a", placeId: "Cellar", radiators: [fireside, door], contacts: [.fireplace()], configuration: HeatingConfiguration(standardPlan: plan))
        let decodedAll = try #require(JSONDecoder().decode(AnyAutomation.self, from: JSONEncoder().encode(AnyAutomation.create(from: all))).automation as? RoomHeating)
        let decodedSome = try #require(JSONDecoder().decode(AnyAutomation.self, from: JSONEncoder().encode(AnyAutomation.create(from: room()))).automation as? RoomHeating)

        #expect(decodedAll.contacts.allSatisfy { $0.affects(door) })
        #expect(decodedSome.contacts.map { $0.affects(door) } == [true, false])
        #expect(decodedSome.contacts.map { $0.affects(fireside) } == [true, true])
    }

    @Test("A configuration deployed before the radiator list existed still decodes")
    func oldJSON() throws {
        let encoded = try JSONEncoder().encode(RoomContact.fireplace())
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(!json.contains("radiators"))   // nothing new on the wire while it is unset
        let contact = try JSONDecoder().decode(RoomContact.self, from: encoded)
        #expect(contact.affects(door))
    }

    @Test("A configuration deployed with the former fireplace switch still decodes, the switch is ignored")
    func switchJSON() throws {
        let json = #"""
        {"fireplace":{"_0":{"switchId":{"placeId":"Keller","name":"Kamin","characteristicType":"switcher"}},"radiators":[{"heatingId":{"placeId":"Cellar","name":"Fireside","characteristicType":"heating"},"targetTemperatureId":{"placeId":"Cellar","name":"Fireside","characteristicType":"targetTemperature"}}]}}
        """#
        let contact = try JSONDecoder().decode(RoomContact.self, from: Data(json.utf8))

        #expect(contact.source == .fireplace)
        #expect(contact.affects(fireside))
        #expect(!contact.affects(door))
    }
}

@Suite("FireplaceTimeout automation")
@HomeManagerActor
struct FireplaceTimeoutTests {
    private let homeManager = MockHomeAdapter()
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let maxDuration = Fireplace.maxDuration

    private func setFireplace(on: Bool, at date: Date) {
        homeManager.fireplaceSwitches.append(FireplaceSwitch(timestamp: date, isOn: on))
    }

    @Test("Before the maximum duration nothing happens")
    func beforeMaxDuration() async throws {
        setFireplace(on: true, at: start)
        let now = start.addingTimeInterval(maxDuration - 60)

        #expect(try await !FireplaceTimeout().shouldTrigger(with: .time(date: now), using: homeManager))
    }

    @Test("After the maximum duration the server ends the fireplace and a push says so")
    func endsAfterMaxDuration() async throws {
        setFireplace(on: true, at: start)
        let now = start.addingTimeInterval(maxDuration)
        let timeout = FireplaceTimeout()

        #expect(try await timeout.shouldTrigger(with: .time(date: now), using: homeManager))
        try await timeout.execute(using: homeManager, now: now)

        #expect(homeManager.fireplaceSwitches.last?.isOn == false)
        #expect(homeManager.storageItems.last { $0.entityId == Fireplace.stateId }?.origin == .server)
        #expect(homeManager.performedActions.isEmpty)
        #expect(homeManager.sentNotifications.map(\.title) == ["Kamin aus"])
        #expect(homeManager.sentNotifications.first?.id == Fireplace.notificationId)
        #expect(homeManager.sentNotifications.first?.message.contains(FireplaceTimeout.durationText(maxDuration)) == true)
    }

    @Test("A fireplace switched off and on again after the timeout trigger is not ended by that run")
    func restartAfterTheTrigger() async throws {
        setFireplace(on: true, at: start)
        let now = start.addingTimeInterval(maxDuration)
        let restartedAt = now.addingTimeInterval(-10)
        let homeManager = self.homeManager
        // the app ends the fireplace and starts it again: the stored switch-on time is new
        homeManager.fireplaceSwitches.append(FireplaceSwitch(timestamp: restartedAt.addingTimeInterval(-1), isOn: false))
        homeManager.fireplaceSwitches.append(FireplaceSwitch(timestamp: restartedAt, isOn: true))

        try await FireplaceTimeout().execute(using: homeManager, now: now)

        #expect(homeManager.fireplaceSwitches.last == FireplaceSwitch(timestamp: restartedAt, isOn: true))
        #expect(homeManager.sentNotifications.isEmpty)
    }

    @Test("The push goes out once per time the fireplace was on, however many ticks follow")
    func pushOnce() async throws {
        setFireplace(on: true, at: start)
        let timeout = FireplaceTimeout()

        for minute in 0..<5 {
            let now = start.addingTimeInterval(maxDuration + Double(minute) * 60)
            if try await timeout.shouldTrigger(with: .time(date: now), using: homeManager) {
                try await timeout.execute(using: homeManager, now: now)
            }
        }
        // a second run that raced the first one finds the fireplace off and sends nothing
        try await timeout.execute(using: homeManager, now: start.addingTimeInterval(maxDuration))

        #expect(homeManager.sentNotifications.count == 1)
        #expect(homeManager.fireplaceSwitches.filter { !$0.isOn }.count == 1)
    }

    @Test("The push names the duration in German", arguments: [
        (2 * 3600.0, "2 Stunden"), (3600.0, "1 Stunde"), (5400.0, "1 Stunde und 30 Minuten"), (60.0, "1 Minute"), (45 * 60.0, "45 Minuten"),
    ])
    func durationText(duration: TimeInterval, text: String) {
        #expect(FireplaceTimeout.durationText(duration) == text)
    }

    @Test("A fireplace that is off is left alone")
    func offStaysOff() async throws {
        setFireplace(on: true, at: start.addingTimeInterval(-60))
        setFireplace(on: false, at: start)

        #expect(try await !FireplaceTimeout().shouldTrigger(with: .time(date: start.addingTimeInterval(maxDuration * 2)), using: homeManager))
    }

    @Test("A fireplace never switched is off: no end, no push")
    func neverSwitched() async throws {
        try await FireplaceTimeout().execute(using: homeManager, now: start.addingTimeInterval(maxDuration * 2))

        #expect(homeManager.fireplaceSwitches.isEmpty)
        #expect(homeManager.sentNotifications.isEmpty)
    }

    @Test("The end is the stored switch-on time plus the maximum duration")
    func endsAt() async throws {
        setFireplace(on: true, at: start)

        #expect(try await Fireplace.state(with: homeManager) == FireplaceState(isOn: true, since: start))
        #expect(try await Fireplace.state(with: homeManager).endsAt == start.addingTimeInterval(maxDuration))
    }

    @Test("Another event does not trigger it")
    func onlyTimeTriggers() async throws {
        setFireplace(on: true, at: start.addingTimeInterval(-maxDuration * 2))

        #expect(try await !FireplaceTimeout().shouldTrigger(with: .sunrise, using: homeManager))
    }

    @Test("It survives the configuration JSON, also one written with the former switch and duration")
    func codable() throws {
        let decoded = try JSONDecoder().decode(AnyAutomation.self, from: JSONEncoder().encode(AnyAutomation.create(from: FireplaceTimeout())))
        let timeout = try #require(decoded.automation as? FireplaceTimeout)
        #expect(timeout.name == "fireplace-timeout")

        let old = #"{"isActive":true,"name":"fireplace-timeout","maxDuration":28800,"fireplace":{"switchId":{"placeId":"Keller","name":"Kamin","characteristicType":"switcher"}}}"#
        let decodedOld = try JSONDecoder().decode(FireplaceTimeout.self, from: Data(old.utf8))
        #expect(decodedOld.name == "fireplace-timeout")
    }
}

@Suite("Fireplace entity")
@HomeManagerActor
struct FireplaceSwitchTests {
    private let homeManager = MockHomeAdapter()
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test("The fireplace is a server-owned switch the app may set")
    func entity() {
        #expect(Fireplace.stateId.isServerOwned)
        #expect(ValueDescriptor.descriptor(for: Fireplace.stateId.characteristicType).isSettableFromApp == true)
    }

    @Test("On since its last change, no HomeKit command, the end derived from the start")
    func on() async throws {
        homeManager.fireplaceSwitches.append(FireplaceSwitch(timestamp: start, isOn: true))

        #expect(try await Fireplace.state(with: homeManager) == FireplaceState(isOn: true, since: start))
        #expect(try await Fireplace.state(with: homeManager).endsAt == start.addingTimeInterval(Fireplace.maxDuration))
        #expect(homeManager.performedActions.isEmpty)
    }

    @Test("Switched off ends it at once")
    func off() async throws {
        homeManager.fireplaceSwitches += [FireplaceSwitch(timestamp: start, isOn: true), FireplaceSwitch(timestamp: start.addingTimeInterval(60), isOn: false)]

        #expect(try await Fireplace.state(with: homeManager) == .off)
    }

    @Test("A fireplace never switched is off")
    func neverSwitched() async throws {
        #expect(try await Fireplace.state(with: homeManager) == .off)
    }

    @Test("The end the server names wins over the one derived from the start")
    func namedEnd() {
        let named = Date(timeIntervalSinceReferenceDate: 900_000_000)
        #expect(FireplaceState(isOn: true, since: start, endsAt: named).endsAt == named)
        #expect(FireplaceState(isOn: true, since: start).endsAt == start.addingTimeInterval(Fireplace.maxDuration))
    }
}

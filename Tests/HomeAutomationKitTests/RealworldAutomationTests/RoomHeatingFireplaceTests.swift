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
    private let fireplace = GenericSwitch(query: .init(placeId: "Keller", name: "Kamin"))
    private let homeManager = MockHomeAdapter()
    private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)   // not at a switch point, whatever the zone is

    private func room() -> RoomHeating {
        RoomHeating("heating-cellar", placeId: "Cellar", radiators: [left], contacts: [.window(window), .fireplace(fireplace)],
                    configuration: HeatingConfiguration(standardPlan: plan))
    }

    private func setFireplace(on: Bool, at date: Date) {
        homeManager.storageItems.append(EntityStorageItem(entityId: fireplace.switchId, timestamp: date, isDeviceOn: on))
    }

    private func setWindow(open: Bool, at date: Date) {
        homeManager.storageItems.append(EntityStorageItem(entityId: window.contactSensorId, timestamp: date, isContactOpen: open))
    }

    private func change(_ id: EntityId) -> HomeEvent {
        .change(entity: homeManager.storageItems.last { $0.entityId == id }!)
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

        #expect(try await room().shouldTrigger(with: change(fireplace.switchId), using: homeManager))
        try await room().execute(using: homeManager, now: noon, sleep: { _ in Issue.record("the fireplace has no delay") })

        #expect(homeManager.performedActions.map(\.action) == [.setHeating(left.heatingId, active: false)])
        #expect(homeManager.performedActions.allSatisfy { $0.heating == .init(reason: .fireplace) })
    }

    @Test("The fireplace going off returns the room to its plan at once, with reason fireplace")
    func fireplaceOffReturnsToPlan() async throws {
        setFireplace(on: true, at: noon)
        let end = noon.addingTimeInterval(3600)
        setFireplace(on: false, at: end)

        #expect(try await room().shouldTrigger(with: change(fireplace.switchId), using: homeManager))
        try await room().execute(using: homeManager, now: end, sleep: { _ in })

        let target = plan.planTarget(at: end)!
        #expect(targets() == [target])
        #expect(homeManager.performedActions.allSatisfy { $0.heating == .init(reason: .fireplace, planTargetInC: target) })
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
        let last = noon.addingTimeInterval(900)
        setWindow(open: false, at: last)

        #expect(try await room().shouldTrigger(with: change(window.contactSensorId), using: homeManager))
        try await room().execute(using: homeManager, now: last, sleep: { _ in })

        #expect(targets() == [plan.planTarget(at: last)!])
    }

    @Test("An unreachable fireplace switch counts as off: the plan keeps running")
    func unreachableIsOff() async throws {
        // no state of the switch at all
        #expect(try await !room().shouldTrigger(with: .serverStarted, using: homeManager))
        try await room().execute(using: homeManager, now: noon, sleep: { _ in })

        #expect(homeManager.performedActions.allSatisfy { if case .setTargetTemperature = $0.action { true } else { $0.action == .setHeating(left.heatingId, active: true) } })
        #expect(targets() == [plan.planTarget(at: noon)!])
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

        #expect(try await !plain.shouldTrigger(with: change(fireplace.switchId), using: homeManager))
        #expect(try await !plain.shouldTrigger(with: .serverStarted, using: homeManager))
    }

    @Test("The fireplace contact survives the configuration JSON")
    func codable() throws {
        let decoded = try JSONDecoder().decode(AnyAutomation.self, from: JSONEncoder().encode(AnyAutomation.create(from: room())))

        let decodedRoom = try #require(decoded.automation as? RoomHeating)
        #expect(decodedRoom.triggerEntityIds == [window.contactSensorId, fireplace.switchId])
    }
}

@Suite("FireplaceTimeout automation")
@HomeManagerActor
struct FireplaceTimeoutTests {
    private let fireplace = Fireplace.switchDevice
    private let homeManager = MockHomeAdapter()
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let eightHours: TimeInterval = 8 * 3600

    private func setFireplace(on: Bool, at date: Date) {
        homeManager.storageItems.append(EntityStorageItem(entityId: fireplace.switchId, timestamp: date, isDeviceOn: on))
    }

    @Test("Before eight hours nothing happens")
    func beforeEightHours() async throws {
        setFireplace(on: true, at: start)
        let now = start.addingTimeInterval(eightHours - 60)

        #expect(try await !FireplaceTimeout().shouldTrigger(with: .time(date: now), using: homeManager))
    }

    @Test("After eight hours the fireplace goes off and a push says so")
    func endsAfterEightHours() async throws {
        setFireplace(on: true, at: start)
        let now = start.addingTimeInterval(eightHours)
        let timeout = FireplaceTimeout()

        #expect(try await timeout.shouldTrigger(with: .time(date: now), using: homeManager))
        try await timeout.execute(using: homeManager, now: now)

        #expect(homeManager.performedActions.map(\.action) == [.turnOff(fireplace.switchId)])
        #expect(homeManager.sentNotifications.map(\.title) == ["Kamin aus"])
        #expect(homeManager.sentNotifications.first?.id == Fireplace.notificationId)
    }

    @Test("A fireplace that is off is left alone")
    func offStaysOff() async throws {
        setFireplace(on: false, at: start)

        #expect(try await !FireplaceTimeout().shouldTrigger(with: .time(date: start.addingTimeInterval(eightHours * 2)), using: homeManager))
    }

    @Test("An unreachable fireplace (no state) is off: no end, no push")
    func unreachable() async throws {
        try await FireplaceTimeout().execute(using: homeManager, now: start.addingTimeInterval(eightHours * 2))

        #expect(homeManager.performedActions.isEmpty)
        #expect(homeManager.sentNotifications.isEmpty)
    }

    @Test("The eight hours count from the switch-on time in the database, not from the restart")
    func startSurvivesRestart() async throws {
        // the database knows the switch went on at `start`; after the restart the adapter's resync put the same
        // state into the cache with the time of the restart
        let restart = start.addingTimeInterval(eightHours - 60)
        homeManager.storedItems[fireplace.switchId] = EntityStorageItem(entityId: fireplace.switchId, timestamp: start, isDeviceOn: true)
        setFireplace(on: true, at: restart)
        let now = start.addingTimeInterval(eightHours + 60)

        #expect(try await FireplaceTimeout().shouldTrigger(with: .time(date: now), using: homeManager))
        #expect(await Fireplace.state(with: homeManager) == FireplaceState(isOn: true, since: start))
        #expect(await Fireplace.state(with: homeManager).endsAt == start.addingTimeInterval(eightHours))
    }

    @Test("Another event does not trigger it")
    func onlyTimeTriggers() async throws {
        setFireplace(on: true, at: start.addingTimeInterval(-eightHours * 2))

        #expect(try await !FireplaceTimeout().shouldTrigger(with: .sunrise, using: homeManager))
    }

    @Test("It survives the configuration JSON")
    func codable() throws {
        let decoded = try JSONDecoder().decode(AnyAutomation.self, from: JSONEncoder().encode(AnyAutomation.create(from: FireplaceTimeout())))

        let timeout = try #require(decoded.automation as? FireplaceTimeout)
        #expect(timeout.fireplace.switchId == Fireplace.switchId)
        #expect(timeout.triggerEntityIds == [Fireplace.switchId])
    }
}

@Suite("Fireplace switch")
@HomeManagerActor
struct FireplaceSwitchTests {
    private let homeManager = MockHomeAdapter()
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func setFireplace(on: Bool, at date: Date) {
        homeManager.storageItems.append(EntityStorageItem(entityId: Fireplace.switchId, timestamp: date, isDeviceOn: on))
    }

    @Test("Switching on an off fireplace turns the switch on and answers with the new state")
    func switchOn() async {
        setFireplace(on: false, at: start)

        let state = await Fireplace.set(isOn: true, with: homeManager, now: start.addingTimeInterval(5))

        #expect(homeManager.performedActions.map(\.action) == [.turnOn(Fireplace.switchId)])
        #expect(state == FireplaceState(isOn: true, since: start.addingTimeInterval(5)))
    }

    @Test("Switching on a fireplace that is on changes nothing and keeps the start")
    func switchOnTwice() async {
        setFireplace(on: true, at: start)

        let state = await Fireplace.set(isOn: true, with: homeManager, now: start.addingTimeInterval(600))

        #expect(homeManager.performedActions.isEmpty)
        #expect(state == FireplaceState(isOn: true, since: start))
    }

    @Test("Switching off turns the switch off")
    func switchOff() async {
        setFireplace(on: true, at: start)

        let state = await Fireplace.set(isOn: false, with: homeManager)

        #expect(homeManager.performedActions.map(\.action) == [.turnOff(Fireplace.switchId)])
        #expect(state == .off)
    }

    @Test("An unreachable switch reads as off")
    func unreachable() async {
        #expect(await Fireplace.state(with: homeManager) == .off)
    }

    @Test("A switch that is on counts since the stored switch-on time, and ends eight hours later")
    func endsAt() async {
        setFireplace(on: true, at: start)

        #expect(await Fireplace.state(with: homeManager).endsAt == start.addingTimeInterval(8 * 3600))
    }
}

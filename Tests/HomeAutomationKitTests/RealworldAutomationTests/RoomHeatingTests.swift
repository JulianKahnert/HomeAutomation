//
//  RoomHeatingTests.swift
//  HomeAutomationKitTests
//

import Foundation
@testable import HAImplementations
import HAModels
import Testing

@Suite("RoomHeating automation")
@HomeManagerActor
struct RoomHeatingTests {
    private let standardPlan = HeatingPlan([
        .init(weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
              switchPoints: [SwitchPoint(hour: 6, targetInC: 21), SwitchPoint(hour: 22, targetInC: 17)]),
        .init(weekdays: [.saturday, .sunday],
              switchPoints: [SwitchPoint(hour: 8, targetInC: 22), SwitchPoint(hour: 23, targetInC: 17)])
    ])
    private let left = Radiator(query: .init(placeId: "Kitchen", name: "Left"))
    private let right = Radiator(query: .init(placeId: "Kitchen", name: "Right"))
    private let windowA = WindowContactSensor(query: .init(placeId: "Kitchen", name: "Window A"))
    private let windowB = WindowContactSensor(query: .init(placeId: "Kitchen", name: "Window B"))
    private let otherWindow = WindowContactSensor(query: .init(placeId: "Bath", name: "Window"))
    private let sleeper = ManualSleeper()
    private let homeManager = MockHomeAdapter()

    private func room(plan: HeatingPlan? = nil) -> RoomHeating {
        RoomHeating("heating-kitchen", placeId: "Kitchen", radiators: [left, right], contacts: [.window(windowA), .window(windowB)], plan: plan, configuration: HeatingConfiguration(standardPlan: standardPlan))
    }

    /// 2026-11-18 is a Wednesday, 2026-11-21 a Saturday.
    private func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    private func targets() -> [Double] {
        homeManager.performedActions.compactMap {
            if case .setTargetTemperature(_, let celsius) = $0.action { return celsius }
            return nil
        }
    }

    // MARK: - switch points

    @Test("Only the minute of a switch point triggers the room")
    func triggersAtSwitchPointsOnly() async throws {
        let room = room()

        #expect(try await room.shouldTrigger(with: .time(date: date(day: 18, hour: 6)), using: homeManager))
        #expect(try await !room.shouldTrigger(with: .time(date: date(day: 18, hour: 6, minute: 1)), using: homeManager))
        #expect(try await !room.shouldTrigger(with: .time(date: date(day: 18, hour: 8)), using: homeManager), "08:00 is a weekend switch point")
        #expect(try await room.shouldTrigger(with: .time(date: date(day: 21, hour: 8)), using: homeManager))
    }

    @Test("A switch point writes its target to every radiator with reason plan")
    func writesPlanTargetToAllRadiators() async throws {
        try await room().execute(using: homeManager, now: date(day: 18, hour: 6))

        let writes = homeManager.performedActions
        #expect(writes.map(\.action) == [
            .setHeating(left.heatingId, active: true), .setTargetTemperature(left.targetTemperatureId, celsius: 21),
            .setHeating(right.heatingId, active: true), .setTargetTemperature(right.targetTemperatureId, celsius: 21)
        ])
        #expect(writes.allSatisfy { $0.heating == .init(reason: .plan, planTargetInC: 21) })
    }

    @Test("The weekend group writes the weekend target")
    func weekendTarget() async throws {
        try await room().execute(using: homeManager, now: date(day: 21, hour: 8))

        #expect(targets() == [22, 22])
    }

    @Test("A room with its own plan ignores the standard plan")
    func ownPlanWins() async throws {
        let own = HeatingPlan([.init(weekdays: [.wednesday], switchPoints: [SwitchPoint(hour: 6, targetInC: 19.5)])])

        try await room(plan: own).execute(using: homeManager, now: date(day: 18, hour: 6))

        #expect(targets() == [19.5, 19.5])
    }

    // MARK: - restart and manual changes

    @Test("A server start and the ticks between switch points write nothing, so a manual change survives")
    func manualChangeSurvivesRestartAndTicks() async throws {
        let room = room()
        homeManager.storageItems = [EntityStorageItem(entityId: left.targetTemperatureId, targetTemperatureInC: 25)]  // set by hand at the device

        #expect(try await !room.shouldTrigger(with: .serverStarted, using: homeManager))
        for minute in [1, 2, 30, 59] {
            #expect(try await !room.shouldTrigger(with: .time(date: date(day: 18, hour: 7, minute: minute)), using: homeManager))
        }
        #expect(try await !room.shouldTrigger(with: .change(entity: EntityStorageItem(entityId: left.targetTemperatureId, targetTemperatureInC: 25)), using: homeManager))
        #expect(homeManager.performedActions.isEmpty)

        // the next switch point overwrites it
        #expect(try await room.shouldTrigger(with: .time(date: date(day: 18, hour: 22)), using: homeManager))
        try await room.execute(using: homeManager, now: date(day: 18, hour: 22))
        #expect(targets() == [17, 17])
    }

    // MARK: - deploy

    @Test("A deploy writes the current plan target once with reason system, and keeps the plan target")
    func deployWritesCurrentPlanTarget() async throws {
        let room = room()

        #expect(try await room.shouldTrigger(with: .configDeployed, using: homeManager))
        try await room.execute(using: homeManager, now: date(day: 18, hour: 12, minute: 17))

        #expect(targets() == [21, 21])
        #expect(homeManager.performedActions.allSatisfy { $0.heating == .init(reason: .system, planTargetInC: 21) })
    }

    @Test("After midnight a deploy writes the last target of the day before")
    func deployBeforeFirstSwitchPoint() async throws {
        try await room().execute(using: homeManager, now: date(day: 19, hour: 3))

        #expect(targets() == [17, 17])
    }

    // MARK: - configuration

    @Test("The room survives the configuration JSON and names its radiators' entities")
    func codableAndEntityIds() throws {
        let room = room()

        let decoded = try JSONDecoder().decode(AnyAutomation.self, from: JSONEncoder().encode(AnyAutomation.create(from: room)))

        let decodedRoom = try #require(decoded.automation as? RoomHeating)
        #expect(decodedRoom.name == "heating-kitchen")
        #expect(decodedRoom.effectivePlan == standardPlan)
        #expect(Set(decodedRoom.getEntityIds()).isSuperset(of: [left.heatingId, left.targetTemperatureId, right.heatingId, right.targetTemperatureId]))
    }

    // MARK: - window-off

    private let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)  // not at a switch point, whatever the zone is

    private func setWindow(_ window: WindowContactSensor, open: Bool, at date: Date) {
        homeManager.storageItems.append(EntityStorageItem(entityId: window.contactSensorId, timestamp: date, isContactOpen: open))
    }

    private func change(_ window: WindowContactSensor) -> HomeEvent {
        .change(entity: homeManager.storageItems.last { $0.entityId == window.contactSensorId }!)
    }

    private func run(_ room: RoomHeating, now: Date) -> Task<Void, any Error> {
        let sleeper = sleeper
        return Task { @HomeManagerActor in try await room.execute(using: homeManager, now: now, sleep: { try await sleeper.sleep(for: $0) }) }
    }

    private func heatingWrites() -> [(HomeManagableAction, HeatingWriteContext.Context?)] {
        homeManager.performedActions.map { ($0.action, $0.heating) }
    }

    @Test("An opening window triggers, waits the delay and then switches every radiator off with reason window")
    func windowOffAfterDelay() async throws {
        let room = room()
        setWindow(windowA, open: true, at: noon)
        #expect(try await room.shouldTrigger(with: change(windowA), using: homeManager))

        let task = run(room, now: noon)
        #expect(await sleeper.nextSleep() == .seconds(10))
        #expect(homeManager.performedActions.isEmpty)
        sleeper.wake()
        try await task.value

        #expect(homeManager.performedActions.map(\.action) == [.setHeating(left.heatingId, active: false), .setHeating(right.heatingId, active: false)])
        #expect(homeManager.performedActions.allSatisfy { $0.heating == .init(reason: .window) })
    }

    @Test("A run that starts after part of the delay waits only the rest")
    func remainingDelay() async throws {
        setWindow(windowA, open: true, at: noon)

        let task = run(room(), now: noon.addingTimeInterval(4))

        #expect(await sleeper.nextSleep() == .seconds(6))
        sleeper.wake()
        try await task.value
        #expect(homeManager.actionCount("setHeating") == 2)
    }

    @Test("A window that closes within the delay writes nothing")
    func openAndCloseWithinDelay() async throws {
        let room = room()
        setWindow(windowA, open: true, at: noon)
        let task = run(room, now: noon)
        _ = await sleeper.nextSleep()

        setWindow(windowA, open: false, at: noon.addingTimeInterval(5))
        #expect(!(try await room.shouldTrigger(with: change(windowA), using: homeManager)), "it never went off, so there is nothing to end")
        sleeper.wake()   // the superseding run would cancel; the sleeping run looks again and sees it closed
        try await task.value

        #expect(homeManager.performedActions.isEmpty)
    }

    @Test("With several windows the room stays off until the last one closes, then returns to the plan at once")
    func severalWindows() async throws {
        let room = room()
        setWindow(windowA, open: true, at: noon)
        setWindow(windowB, open: true, at: noon.addingTimeInterval(3))
        setWindow(windowA, open: false, at: noon.addingTimeInterval(60))   // B is still open
        let afterA = noon.addingTimeInterval(60)

        #expect(try await room.shouldTrigger(with: change(windowA), using: homeManager))
        try await room.execute(using: homeManager, now: afterA, sleep: { _ in })
        #expect(homeManager.performedActions.map(\.action) == [.setHeating(left.heatingId, active: false), .setHeating(right.heatingId, active: false)])

        homeManager.performedActions.removeAll()
        let afterB = noon.addingTimeInterval(120)
        setWindow(windowB, open: false, at: afterB)
        #expect(try await room.shouldTrigger(with: change(windowB), using: homeManager))
        try await room.execute(using: homeManager, now: afterB, sleep: { _ in })

        #expect(targets() == [room.effectivePlan.planTarget(at: afterB)!, room.effectivePlan.planTarget(at: afterB)!])
        #expect(homeManager.performedActions.allSatisfy { $0.heating?.reason == .window && $0.heating?.planTargetInC != nil })
    }

    @Test("Closing returns to the plan target, not to an old manual value")
    func closeReturnsToPlan() async throws {
        homeManager.storageItems = [EntityStorageItem(entityId: left.targetTemperatureId, targetTemperatureInC: 25)]  // manual value before
        setWindow(windowA, open: true, at: noon)
        setWindow(windowA, open: false, at: noon.addingTimeInterval(600))
        let now = noon.addingTimeInterval(600)

        try await room().execute(using: homeManager, now: now, sleep: { _ in })

        let target = standardPlan.planTarget(at: now)!
        #expect(targets() == [target, target])
        #expect(!targets().contains(25))
    }

    @Test("A switch point while a window is open leaves the radiators off")
    func switchPointKeepsOff() async throws {
        let switchPoint = date(day: 18, hour: 22)
        setWindow(windowA, open: true, at: switchPoint.addingTimeInterval(-3600))

        try await room().execute(using: homeManager, now: switchPoint, sleep: { _ in })

        #expect(targets().isEmpty)
        #expect(homeManager.performedActions.map(\.action) == [.setHeating(left.heatingId, active: false), .setHeating(right.heatingId, active: false)])
    }

    @Test("Another room's window does not trigger the room")
    func otherRoomUnaffected() async throws {
        setWindow(otherWindow, open: true, at: noon)

        #expect(try await !room().shouldTrigger(with: .change(entity: EntityStorageItem(entityId: otherWindow.contactSensorId, timestamp: noon, isContactOpen: true)), using: homeManager))
    }

    @Test("A restart with an open window switches the room off at once; a restart with closed windows writes nothing")
    func restart() async throws {
        let room = room()
        setWindow(windowA, open: true, at: noon.addingTimeInterval(-3600))   // opened long before the restart
        setWindow(windowB, open: false, at: noon.addingTimeInterval(-7200))

        #expect(try await !room.shouldTrigger(with: .serverStarted, using: homeManager))
        // the adapter re-sends every contact after the handshake
        #expect(try await room.shouldTrigger(with: change(windowA), using: homeManager))
        #expect(try await !room.shouldTrigger(with: change(windowB), using: homeManager))
        try await room.execute(using: homeManager, now: noon, sleep: { _ in Issue.record("must not wait"); })

        #expect(homeManager.actionCount("setHeating") == 2)
        #expect(targets().isEmpty)
    }

    @Test("Window contacts survive the configuration JSON and name their entities")
    func contactsCodable() throws {
        let decoded = try JSONDecoder().decode(AnyAutomation.self, from: JSONEncoder().encode(AnyAutomation.create(from: room())))

        let decodedRoom = try #require(decoded.automation as? RoomHeating)
        #expect(decodedRoom.triggerEntityIds == [windowA.contactSensorId, windowB.contactSensorId])
        #expect(Set(decodedRoom.getEntityIds()).isSuperset(of: [windowA.contactSensorId, windowB.contactSensorId]))
    }
}

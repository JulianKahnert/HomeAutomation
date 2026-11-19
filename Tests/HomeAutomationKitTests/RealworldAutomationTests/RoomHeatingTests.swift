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
    private let homeManager = MockHomeAdapter()

    private func room(plan: HeatingPlan? = nil) -> RoomHeating {
        RoomHeating("heating-kitchen", placeId: "Kitchen", radiators: [left, right], plan: plan, configuration: HeatingConfiguration(standardPlan: standardPlan))
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
        #expect(Set(decodedRoom.getEntityIds()) == [left.heatingId, left.targetTemperatureId, right.heatingId, right.targetTemperatureId])
    }
}

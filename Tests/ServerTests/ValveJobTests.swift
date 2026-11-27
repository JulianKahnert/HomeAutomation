//
//  ValveJobTests.swift
//  HomeAutomation
//

import Foundation
@testable import HAModels
@testable import Server
import Testing

private struct Asleep: Error {}

private final class Fed: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [EntityStorageItem] = []
    func add(_ item: EntityStorageItem) { lock.lock(); stored.append(item); lock.unlock() }
    var items: [EntityStorageItem] { lock.lock(); defer { lock.unlock() }; return stored }
}

struct ValveJobTests {
    private let bath = Thermostat(placeId: "bath", name: "Thermo", characteristicsName: nil)
    private let kitchen = Thermostat(placeId: "kitchen", name: "Thermo", characteristicsName: nil)

    private func item(_ thermostat: Thermostat, percent: Int) -> EntityStorageItem {
        EntityStorageItem(entityId: EntityId(placeId: thermostat.placeId, name: thermostat.name, characteristicsName: nil, characteristic: .valvePosition),
                          valvePositionPercent: percent)
    }

    @Test func feedsEveryValueWithTheJobsOrigin() async throws {
        let fed = Fed()
        let bathItem = item(bath, percent: 30)
        let job = ValveJob(listThermostats: { [bath] }, readThermostat: { _ in [bathItem] }, feed: fed.add)

        try await job.run(plannedAt: Date())

        #expect(fed.items.map(\.valvePositionPercent) == [30])
        #expect(fed.items.map(\.origin) == [.job("ValveJob")])
        #expect(job.cadence == .minutes(5))
    }

    @Test func aSleepingThermostatDelaysNoOtherAndTheRunSucceeds() async throws {
        let fed = Fed()
        let kitchenItem = item(kitchen, percent: 10)
        let (bathName, kitchenName) = (bath.placeId, kitchen.placeId)
        let job = ValveJob(listThermostats: { [bath, kitchen] },
                           readThermostat: { thermostat in
            if thermostat.placeId == bathName { throw Asleep() }
            #expect(thermostat.placeId == kitchenName)
            return [kitchenItem]
        },
                           feed: fed.add)

        try await job.run(plannedAt: Date())

        #expect(fed.items.map(\.entityId.placeId) == ["kitchen"])
    }

    @Test func aFailingListFailsTheRun() async {
        let job = ValveJob(listThermostats: { throw Asleep() }, readThermostat: { _ in [] }, feed: { _ in })
        await #expect(throws: Asleep.self) { try await job.run(plannedAt: Date()) }
    }
}

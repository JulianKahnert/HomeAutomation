//
//  AutomationLaneTests.swift
//  HomeAutomationKit
//

import Foundation
import HAApplicationLayer
import HAModels
import Testing

/// Records what `shouldTrigger` saw and can hold it open until released.
private actor LaneProbe {
    private(set) var seen: [HomeEvent] = []
    private var held = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func hold() { held = true }
    func release() {
        held = false
        waiters.forEach { $0.resume() }
        waiters = []
    }
    func check(_ event: HomeEvent) async {
        seen.append(event)
        if held {
            await withCheckedContinuation { waiters.append($0) }
        }
    }
    func waitForSeen(_ count: Int) async {
        while seen.count < count { try? await Task.sleep(for: .milliseconds(1)) }
    }
}

private struct LaneAutomation: Automatable {
    var isActive = true
    let name: String
    var collapsesChanges = true
    var triggerEntityIds: Set<EntityId> { [] }
    var probe: LaneProbe?
    var recordsRuns: Bool { false }

    enum CodingKeys: CodingKey { case isActive, name, collapsesChanges }

    func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        await probe?.check(event)
        return false
    }

    func execute(using hm: HomeManagable) async throws {}
}

@HomeManagerActor
struct AutomationLaneTests {
    let homeManager = MockHomeAdapter()
    let motion = EntityId(placeId: "p", name: "n", characteristicsName: "Motion", characteristic: .motionSensor)

    private func change(_ motion: Bool, id: EntityId? = nil) -> HomeEvent {
        .change(entity: EntityStorageItem(entityId: id ?? self.motion, motionDetected: motion))
    }

    private func makeService(_ automations: [LaneAutomation]) throws -> AutomationService {
        try AutomationService(using: homeManager, runs: InMemoryAutomationRunRepository(), automations: automations)
    }

    @Test func aHeldShouldTriggerDelaysNoOtherAutomation() async throws {
        let slow = LaneProbe(), fast = LaneProbe()
        await slow.hold()
        let service = try makeService([LaneAutomation(name: "slow", probe: slow), LaneAutomation(name: "fast", probe: fast)])

        await service.trigger(with: .sunrise)
        await service.trigger(with: .sunset)

        await fast.waitForSeen(2)
        #expect(await fast.seen == [.sunrise, .sunset])
        #expect(await slow.seen == [.sunrise])
        await slow.release()
    }

    @Test func eventsReachOneAutomationInOrder() async throws {
        let probe = LaneProbe()
        let service = try makeService([LaneAutomation(name: "a", probe: probe)])

        await service.trigger(with: .sunrise)
        await service.trigger(with: .serverStarted)
        await service.trigger(with: .sunset)

        await probe.waitForSeen(3)
        #expect(await probe.seen == [.sunrise, .serverStarted, .sunset])
    }

    @Test func waitingChangesOfTheSameEntityCollapseToTheNewest() async throws {
        let probe = LaneProbe()
        await probe.hold()
        let service = try makeService([LaneAutomation(name: "a", probe: probe)])
        let other = EntityId(placeId: "p", name: "o", characteristicsName: "Motion", characteristic: .motionSensor)

        await service.trigger(with: .sunrise)
        await probe.waitForSeen(1)
        await service.trigger(with: change(true))
        await service.trigger(with: change(true, id: other))
        await service.trigger(with: change(false))
        await probe.release()

        await service.waitUntilIdle()
        #expect(await probe.seen.count == 3)
        let seen = await probe.seen
        guard case .change(let second) = seen[1], case .change(let third) = seen[2] else {
            Issue.record("expected two changes")
            return
        }
        #expect(second.entityId == other)
        #expect(third.entityId == motion)
        #expect(third.motionDetected == false)
    }

    @Test func eventsWithoutStateNeverCollapse() async throws {
        let probe = LaneProbe()
        await probe.hold()
        let service = try makeService([LaneAutomation(name: "a", probe: probe)])

        await service.trigger(with: .sunrise)
        await probe.waitForSeen(1)
        for event in [HomeEvent.sunrise, .sunrise, .sunset, .sunset, .serverStarted, .serverStarted, .configDeployed, .configDeployed, .time(date: Date())] {
            await service.trigger(with: event)
        }
        await probe.release()

        await probe.waitForSeen(10)
        #expect(await probe.seen.count == 10)
    }

    @Test func aLaneCanBeNonCollapsing() async throws {
        let probe = LaneProbe()
        await probe.hold()
        let service = try makeService([LaneAutomation(name: "a", collapsesChanges: false, probe: probe)])

        await service.trigger(with: .sunrise)
        await probe.waitForSeen(1)
        await service.trigger(with: change(true))
        await service.trigger(with: change(false))
        await probe.release()

        await probe.waitForSeen(3)
        #expect(await probe.seen.count == 3)
    }

    @Test func aBacklogShowsUpAsLaneAge() async throws {
        let probe = LaneProbe()
        await probe.hold()
        let service = try makeService([LaneAutomation(name: "stuck", probe: probe), LaneAutomation(name: "idle")])

        await service.trigger(with: .sunrise)
        await probe.waitForSeen(1)

        let later = Date().addingTimeInterval(120)
        let ages = await service.laneAges(now: later)
        #expect(ages["stuck"] ?? 0 >= 119)
        #expect(ages["idle"] == 0)
        await probe.release()
        await service.waitUntilIdle()
        #expect(await service.laneAges(now: later)["stuck"] == 0)
    }
}

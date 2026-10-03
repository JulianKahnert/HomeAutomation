//
//  OverviewFeatureTests.swift
//  ControllerTests
//

import ComposableArchitecture
@testable import Controller
import Foundation
import HAModels
import Synchronization
import Testing

@MainActor
@Suite("OverviewFeature")
struct OverviewFeatureTests {
    private let light = EntityId(placeId: "Bath", name: "Mirror", characteristicsName: nil, characteristic: .switcher)

    private func run(_ outcome: AutomationRun.Outcome, error: String? = nil) -> AutomationRun {
        AutomationRun(
            automationName: "Night Light",
            startedAt: Date(timeIntervalSince1970: 0),
            trigger: AutomationTrigger(kind: .sunset, entityId: nil, summary: "Sunset"),
            outcome: outcome,
            errorDescription: error
        )
    }

    private func command(_ status: ActionLogItem.Status) -> ActionLogItem {
        ActionLogItem(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 0),
            entityId: light,
            actionName: "on",
            detailDescription: "turnOn",
            hasCacheHit: false,
            status: status
        )
    }

    @Test("hints come from failed runs and failed commands per device")
    func hintsFromFailures() {
        var state = OverviewFeature.State()
        state.recentRuns = [run(.failed, error: "not reachable"), run(.completed)]
        state.recentActions = [command(.failed), command(.failed), command(.executed)]

        #expect(state.hints == ["Night Light failed: not reachable", "Mirror (Bath): 2 failed commands"])
    }

    @Test("refresh fills the status, drops commands older than a day and sorts the shared automations")
    func refreshFillsSnapshot() async {
        let now = Date(timeIntervalSince1970: 100_000)
        let completed = run(.completed)
        // Stamped at 1970, long before the 24 hour window.
        let oldCommand = command(.executed)
        let alpha = AutomationInfo(name: "Alpha", isActive: true, isRunning: false)
        let zebra = AutomationInfo(name: "Zebra", isActive: true, isRunning: false)
        let store = TestStore(initialState: OverviewFeature.State()) {
            OverviewFeature()
        } withDependencies: {
            $0.date.now = now
            $0.serverClient.getAutomations = { [zebra, alpha] }
            $0.serverClient.getRecentRuns = { _, _ in [completed] }
            $0.serverClient.getActions = { _, _ in [oldCommand] }
        }

        await store.send(.refresh)
        await store.receive(\.refreshResponse.success) {
            $0.isHealthy = true
            $0.lastUpdated = now
            $0.recentRuns = [completed]
            $0.recentActions = []
            $0.$automations.withLock { $0 = [alpha, zebra] }
        }
    }

    @Test("stopping an automation refreshes the overview")
    func stopRefreshes() async {
        let stopped = Mutex<[String]>([])
        let store = TestStore(initialState: OverviewFeature.State()) {
            OverviewFeature()
        } withDependencies: {
            $0.date.now = Date(timeIntervalSince1970: 100_000)
            $0.serverClient.stop = { name in stopped.withLock { $0.append(name) } }
        }
        store.exhaustivity = .off

        await store.send(.stopButtonTapped("Night Light"))
        await store.receive(\.refresh)
        await store.receive(\.refreshResponse.success)

        #expect(stopped.withLock { $0 } == ["Night Light"])
    }

    @Test("polls every 30 seconds until the task is cancelled")
    func pollingStopsOnCancel() async {
        let clock = TestClock()
        let store = TestStore(initialState: OverviewFeature.State()) {
            OverviewFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.date.now = Date(timeIntervalSince1970: 100_000)
        }
        store.exhaustivity = .off

        let task = await store.send(.task)
        await store.receive(\.refresh)
        await store.receive(\.refreshResponse)

        await clock.advance(by: .seconds(30))
        await store.receive(\.refresh)
        await store.receive(\.refreshResponse)

        await task.cancel()
        await clock.advance(by: .seconds(60))
        #expect(store.state.isHealthy == true)
    }

    @Test("a run's Open Automation button switches to its tab and opens the details")
    func openAutomationFromRun() async {
        var state = AppFeature.State()
        state.automations.$automations.withLock {
            $0 = [AutomationInfo(name: "Night Light", isActive: true, isRunning: false, type: "MotionAtNight")]
        }
        state.overview.path.append(.run(RunDetailFeature.State(run: run(.completed))))
        let store = TestStore(initialState: state) {
            AppFeature()
        }
        store.exhaustivity = .off

        await store.send(\.overview.path[id: 0].run.openAutomationButtonTapped)
        await store.receive(\.overview.delegate)
        await store.receive(\.automations.openAutomation)
        #expect(store.state.selectedTab == .automations)
        #expect(store.state.automations.path.first?.details?.automation.name == "Night Light")
    }
}

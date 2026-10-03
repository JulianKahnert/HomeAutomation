//
//  OverviewFeatureTests.swift
//  ControllerTests
//

import ComposableArchitecture
@testable import Controller
import Foundation
import HAModels
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

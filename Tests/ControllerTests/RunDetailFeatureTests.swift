//
//  RunDetailFeatureTests.swift
//  ControllerTests
//

import ComposableArchitecture
@testable import Controller
import Foundation
import HAModels
import Testing

@MainActor
@Suite("RunDetailFeature")
struct RunDetailFeatureTests {
    @Test("loads the commands of its run")
    func loadsCommandsByRunId() async {
        let run = AutomationRun(
            automationName: "Hallway",
            startedAt: Date(timeIntervalSince1970: 0),
            trigger: AutomationTrigger(kind: .sunset, entityId: nil, summary: "Sunset"),
            outcome: .completed
        )
        let command = ActionLogItem(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: 1),
            entityId: EntityId(placeId: "Hall", name: "Light", characteristicsName: nil, characteristic: .switcher),
            actionName: "on",
            detailDescription: "turnOn",
            hasCacheHit: false,
            runId: run.id,
            status: .executed
        )
        let store = TestStore(initialState: RunDetailFeature.State(run: run)) {
            RunDetailFeature()
        } withDependencies: {
            $0.serverClient.getActions = { _, runId in runId == run.id ? [command] : [] }
        }

        await store.send(.task)
        await store.receive(\.actionsResponse) {
            $0.actions = [command]
        }
    }
}

//
//  ActivityFeedFeatureTests.swift
//  ControllerTests
//

@testable import Controller
import Foundation
import HAModels
import Testing

@Suite("ActivityFeedFeature")
struct ActivityFeedFeatureTests {
    private let run = AutomationRun(
        automationName: "Night Light",
        startedAt: Date(timeIntervalSince1970: 10),
        trigger: AutomationTrigger(kind: .sunset, entityId: nil, summary: "Sunset"),
        outcome: .completed
    )
    private let command = ActionLogItem(
        id: UUID(),
        timestamp: Date(timeIntervalSince1970: 20),
        entityId: EntityId(placeId: "Bath", name: "Mirror", characteristicsName: nil, characteristic: .switcher),
        actionName: "on",
        detailDescription: "turnOn",
        hasCacheHit: false,
        status: .executed
    )

    @Test("entries mix runs and commands, newest first")
    func entriesNewestFirst() {
        let state = ActivityFeedFeature.State(runs: [run], actions: [command])

        #expect(state.entries.map(\.id) == [command.id, run.id])
    }

    @Test("filter limits the entries to runs or commands")
    func filterLimitsEntries() {
        var state = ActivityFeedFeature.State(runs: [run], actions: [command])

        state.filter = .runs
        #expect(state.entries.map(\.id) == [run.id])

        state.filter = .commands
        #expect(state.entries.map(\.id) == [command.id])
    }
}

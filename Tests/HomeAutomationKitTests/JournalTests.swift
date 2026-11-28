//
//  JournalTests.swift
//  HomeAutomationKit
//

import Foundation
@testable import HAApplicationLayer
import HAModels
import Testing

struct JournalTests {
    private let radiator = EntityId(placeId: "Kitchen", name: "Radiator", characteristicsName: nil, characteristic: .targetTemperature)
    private let switchId = EntityId(placeId: "room", name: "light", characteristicsName: nil, characteristic: .switcher)

    private func makeHomeManager(journal: Journal, adapter: (any EntityAdapterable)? = nil) async -> HomeManager {
        await HomeManager(getAdapter: { adapter },
                          storageRepo: MockStorageRepository(),
                          notificationSender: MockNotificationSender(),
                          location: Location(latitude: 0, longitude: 0),
                          journal: journal,
                          retryTicks: AsyncStream { _ in })
    }

    @Test("A command and a push of a run are entries linked by the run id")
    func commandAndPushShareTheRun() async {
        let journal = Journal(store: InMemoryJournalStore())
        let homeManager = await makeHomeManager(journal: journal)
        let runId = UUID()

        await AutomationRunContext.$runId.withValue(runId) {
            await HeatingWriteContext.withReason(.window) {
                await homeManager.perform(.setHeating(radiator, active: false))
            }
            await homeManager.deliver(.push(title: "Fenster", message: "offen", id: "window"))
        }
        await homeManager.deliver(.push(title: "Ohne Lauf", message: "x", id: "other"))
        await journal.flush()

        let commands = await journal.commands(limit: nil, runId: runId)
        #expect(commands.map(\.reason) == [.window])
        #expect(commands.map(\.runId) == [runId])
        let pushes = await journal.pushes(runId: runId)
        #expect(pushes.map(\.title) == ["Fenster"])
        #expect(await journal.pushes(runId: nil).count == 2)
    }

    @Test("A command is never delayed by a database that hangs")
    func slowDatabaseDoesNotDelayCommands() async {
        let store = StallingStore()
        let journal = Journal(store: store)
        let homeManager = await makeHomeManager(journal: journal)

        // Returns although the journal write never finishes.
        await homeManager.perform(.turnOn(switchId))
        await homeManager.deliver(.push(title: "t", message: "m", id: "i"))
    }

    @Test("A flush whose marker was dropped from a full queue still returns")
    func flushReturnsWhenItsMarkerWasDropped() async {
        let journal = Journal(store: StallingStore())

        journal.recordPush(JournalPush(runId: nil, title: "t", message: "m", pushId: "i"))
        let flushing = Task { await journal.flush() }
        while journal.enqueuedCount < 2 { await Task.yield() }
        // More writes than the queue holds push the oldest items out, the flush marker among them.
        for _ in 0...Journal.queueLimit {
            journal.recordPush(JournalPush(runId: nil, title: "t", message: "m", pushId: "i"))
        }

        await flushing.value
    }

    @Test("A failing database fails no command and later writes still land")
    func failingDatabaseDoesNotFailCommands() async {
        let store = FlakyStore()
        let journal = Journal(store: store)
        let homeManager = await makeHomeManager(journal: journal)

        await homeManager.perform(.turnOn(switchId))
        await journal.flush()
        await homeManager.deliver(.push(title: "t", message: "m", id: "i"))
        await journal.flush()

        #expect(await store.pushes.count == 1)
    }

    @Test("deleteEntries removes entries of every kind older than the date")
    func deleteEntriesRemovesOldEntriesOfEveryKind() async throws {
        let store = InMemoryJournalStore()
        let journal = Journal(store: store)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let old = now.addingTimeInterval(-40 * 86_400)
        let trigger = AutomationTrigger(kind: .sunset, entityId: nil, summary: "Sunset")
        try await store.add(AutomationRun(automationName: "old", startedAt: old, trigger: trigger, outcome: .completed))
        try await store.add(AutomationRun(automationName: "new", startedAt: now, trigger: trigger, outcome: .completed))
        try await store.addCommand(ActionLogItem(timestamp: old, action: .turnOn(switchId)))
        try await store.addCommand(ActionLogItem(timestamp: now, action: .turnOn(switchId)))
        try await store.addPush(JournalPush(timestamp: old, runId: nil, title: "o", message: "o", pushId: "o"))
        try await store.addPush(JournalPush(timestamp: now, runId: nil, title: "n", message: "n", pushId: "n"))

        try await journal.deleteEntries(olderThan: now.addingTimeInterval(-30 * 86_400))

        #expect(try await store.latestRuns(since: .distantPast, limit: 10).map(\.automationName) == ["new"])
        #expect(await journal.commands(limit: nil, runId: nil).count == 1)
        #expect(await journal.pushes(runId: nil).map(\.title) == ["n"])
    }

    @Test("deleteEntries keeps radiator commands with a heating reason for good, and with them the last command of every radiator")
    func deleteEntriesKeepsHeatingCommands() async throws {
        let store = InMemoryJournalStore()
        let now = Date(timeIntervalSince1970: 100_000_000)
        let old = now.addingTimeInterval(-400 * 86_400)
        let older = now.addingTimeInterval(-500 * 86_400)
        try await store.addCommand(ActionLogItem(timestamp: older, action: .setTargetTemperature(radiator, celsius: 19), reason: .plan))
        try await store.addCommand(ActionLogItem(timestamp: old, action: .setTargetTemperature(radiator, celsius: 21), reason: .fireplace))
        try await store.addCommand(ActionLogItem(timestamp: old, action: .turnOn(switchId)))

        try await store.deleteEntries(olderThan: now.addingTimeInterval(-30 * 86_400))

        let kept = try await store.commands(limit: nil, runId: nil)
        #expect(Set(kept.compactMap(\.reason)) == [.fireplace, .plan])
        #expect(kept.allSatisfy { $0.reason != nil })
        #expect(try await store.lastHeatingWrites().first?.value == 21)
    }
}

private struct StoreError: Error {}

/// Every write waits for ever.
private actor StallingStore: JournalStore {
    private func stall() async throws {
        try await Task.sleep(for: .seconds(3_600))
    }

    func add(_ run: AutomationRun) async throws { try await stall() }
    func finish(_ id: UUID, outcome: AutomationRun.Outcome, endedAt: Date, errorDescription: String?) async throws { try await stall() }
    func runs(for automationName: String, startDate: Date?, endDate: Date?, limit: Int) async throws -> [AutomationRun] { [] }
    func latestRuns(since date: Date, limit: Int) async throws -> [AutomationRun] { [] }
    func latestRunPerAutomation() async throws -> [String: AutomationRun] { [:] }
    func markRunningAsInterrupted() async throws {}
    func addCommand(_ command: ActionLogItem) async throws { try await stall() }
    func setCommandStatus(_ id: UUID, to status: ActionLogItem.Status) async throws { try await stall() }
    func commands(limit: Int?, runId: UUID?) async throws -> [ActionLogItem] { [] }
    func heatingWrites(placeId: String, startDate: Date?, endDate: Date?) async throws -> [ActionLogItem] { [] }
    func lastHeatingWrites() async throws -> [ActionLogItem] { [] }
    func addPush(_ push: JournalPush) async throws { try await stall() }
    func pushes(runId: UUID?) async throws -> [JournalPush] { [] }
    func deleteEntries(olderThan date: Date) async throws {}
}

/// Command writes throw, push writes succeed.
private actor FlakyStore: JournalStore {
    private(set) var pushes: [JournalPush] = []

    func add(_ run: AutomationRun) async throws { throw StoreError() }
    func finish(_ id: UUID, outcome: AutomationRun.Outcome, endedAt: Date, errorDescription: String?) async throws { throw StoreError() }
    func runs(for automationName: String, startDate: Date?, endDate: Date?, limit: Int) async throws -> [AutomationRun] { throw StoreError() }
    func latestRuns(since date: Date, limit: Int) async throws -> [AutomationRun] { throw StoreError() }
    func latestRunPerAutomation() async throws -> [String: AutomationRun] { throw StoreError() }
    func markRunningAsInterrupted() async throws {}
    func addCommand(_ command: ActionLogItem) async throws { throw StoreError() }
    func setCommandStatus(_ id: UUID, to status: ActionLogItem.Status) async throws { throw StoreError() }
    func commands(limit: Int?, runId: UUID?) async throws -> [ActionLogItem] { throw StoreError() }
    func heatingWrites(placeId: String, startDate: Date?, endDate: Date?) async throws -> [ActionLogItem] { throw StoreError() }
    func lastHeatingWrites() async throws -> [ActionLogItem] { throw StoreError() }
    func addPush(_ push: JournalPush) async throws { pushes.append(push) }
    func pushes(runId: UUID?) async throws -> [JournalPush] { pushes }
    func deleteEntries(olderThan date: Date) async throws { throw StoreError() }
}

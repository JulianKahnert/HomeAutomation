//
//  HeatingFixture.swift
//  HomeAutomationKit
//

import Foundation
import HAApplicationLayer
import HAModels

/// A radiator command as a test seeds it: the journal row plus the plan target that was current at the time.
struct HeatingFixture {
    let command: ActionLogItem
    let planTargetInC: Double?

    var timestamp: Date { command.timestamp }
    var placeId: String { command.placeId }

    init(timestamp: Date = Date(), action: HomeManagableAction, reason: HeatingWriteReason, planTargetInC: Double? = nil) {
        command = ActionLogItem(timestamp: timestamp, action: action, reason: reason)
        self.planTargetInC = planTargetInC
    }

    /// The stored state of the room's plan target entity that goes with this write, `nil` without a plan target.
    func planTargetItem() -> EntityStorageItem? {
        planTargetInC.map { EntityStorageItem(entityId: HeatingRoomSources.planTargetId(placeId: placeId), timestamp: timestamp, targetTemperatureInC: $0, origin: .server) }
    }
}

/// A journal that holds the seeded radiator commands, as the room detail reads them.
func seededJournal(_ fixtures: [HeatingFixture] = []) -> InMemoryJournalStore {
    InMemoryJournalStore(commands: fixtures.map(\.command))
}

/// A seeded radiator command without a plan target.
func seededWrite(timestamp: Date, action: HomeManagableAction, reason: HeatingWriteReason) -> ActionLogItem {
    HeatingFixture(timestamp: timestamp, action: action, reason: reason).command
}

/// A journal that remembers the `startDate` of every radiator command lookup and answers like the store it wraps.
actor StartSpyJournal: JournalStore {
    private let store: InMemoryJournalStore
    /// `nil` for an open start.
    private(set) var requestedStarts: [Date?] = []

    init(_ store: InMemoryJournalStore) { self.store = store }

    func heatingWrites(placeId: String, startDate: Date?, endDate: Date?) async throws -> [ActionLogItem] {
        requestedStarts.append(startDate)
        return try await store.heatingWrites(placeId: placeId, startDate: startDate, endDate: endDate)
    }

    func add(_ run: AutomationRun) async throws { try await store.add(run) }
    func finish(_ id: UUID, outcome: AutomationRun.Outcome, endedAt: Date, errorDescription: String?) async throws {
        try await store.finish(id, outcome: outcome, endedAt: endedAt, errorDescription: errorDescription)
    }
    func runs(for automationName: String, startDate: Date?, endDate: Date?, limit: Int) async throws -> [AutomationRun] {
        try await store.runs(for: automationName, startDate: startDate, endDate: endDate, limit: limit)
    }
    func latestRuns(since date: Date, limit: Int) async throws -> [AutomationRun] { try await store.latestRuns(since: date, limit: limit) }
    func latestRunPerAutomation() async throws -> [String: AutomationRun] { try await store.latestRunPerAutomation() }
    func markRunningAsInterrupted() async throws { try await store.markRunningAsInterrupted() }
    func addCommand(_ command: ActionLogItem) async throws { try await store.addCommand(command) }
    func setCommandStatus(_ id: UUID, to status: ActionLogItem.Status) async throws { try await store.setCommandStatus(id, to: status) }
    func commands(limit: Int?, runId: UUID?) async throws -> [ActionLogItem] { try await store.commands(limit: limit, runId: runId) }
    func lastHeatingWrites() async throws -> [ActionLogItem] { try await store.lastHeatingWrites() }
    func addPush(_ push: JournalPush) async throws { try await store.addPush(push) }
    func pushes(runId: UUID?) async throws -> [JournalPush] { try await store.pushes(runId: runId) }
    func deleteEntries(olderThan date: Date) async throws { try await store.deleteEntries(olderThan: date) }
}

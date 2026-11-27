//
//  Journal.swift
//  HomeAutomationKit
//

import Foundation
import HAModels
import Logging

/// The facade over the journal table: commands and pushes are written off the caller's path (ADR-004).
///
/// A write is queued and returns at once; one task writes the queue in order, so a command entry exists
/// before its status changes. A failing or slow database costs entries (logged), never a command.
/// Runs are written through ``AutomationRunRepository`` by the ``AutomationService``.
public final class Journal: Sendable {
    /// Writes waiting for the database; beyond this the oldest are dropped.
    public static let queueLimit = 1_000
    /// The most commands one read returns.
    public static let maxCommands = 1_000

    private static let logger = Logger(label: "Journal")

    private let store: any JournalStore
    private let queue: AsyncStream<@Sendable () async throws -> Void>.Continuation

    public init(store: any JournalStore) {
        self.store = store
        let (stream, queue) = AsyncStream<@Sendable () async throws -> Void>.makeStream(bufferingPolicy: .bufferingNewest(Self.queueLimit))
        self.queue = queue
        Task.detached(priority: .background) {
            for await write in stream {
                do {
                    try await write()
                } catch {
                    Self.logger.error("Failed to write the journal", metadata: ["error": "\(error)"])
                }
            }
        }
    }

    deinit {
        queue.finish()
    }

    public func recordCommand(_ command: ActionLogItem) {
        enqueue { [store] in try await store.addCommand(command) }
    }

    public func markCommandFailed(_ id: UUID) {
        enqueue { [store] in try await store.setCommandStatus(id, to: .failed) }
    }

    public func recordPush(_ push: JournalPush) {
        enqueue { [store] in try await store.addPush(push) }
    }

    /// Newest first; empty when the database fails.
    public func commands(limit: Int?, runId: UUID?) async -> [ActionLogItem] {
        do {
            return try await store.commands(limit: min(limit ?? Self.maxCommands, Self.maxCommands), runId: runId)
        } catch {
            Self.logger.error("Failed to read the commands of the journal", metadata: ["error": "\(error)"])
            return []
        }
    }

    public func pushes(runId: UUID?) async -> [JournalPush] {
        do {
            return try await store.pushes(runId: runId)
        } catch {
            Self.logger.error("Failed to read the pushes of the journal", metadata: ["error": "\(error)"])
            return []
        }
    }

    public func clearCommands() async {
        do {
            try await store.clearCommands()
        } catch {
            Self.logger.error("Failed to clear the commands of the journal", metadata: ["error": "\(error)"])
        }
    }

    /// Removes entries of every kind older than `date`; the cleanup calls this.
    public func deleteEntries(olderThan date: Date) async throws {
        try await store.deleteEntries(olderThan: date)
    }

    /// Returns once every write queued so far was tried.
    public func flush() async {
        await withCheckedContinuation { continuation in
            enqueue { continuation.resume() }
        }
    }

    private func enqueue(_ write: @escaping @Sendable () async throws -> Void) {
        queue.yield(write)
    }
}

/// Keeps the journal in memory; for tests and previews.
public actor InMemoryJournalStore: JournalStore {
    private var runStore: [UUID: AutomationRun] = [:]
    private var commandStore: [ActionLogItem] = []
    private var pushStore: [JournalPush] = []

    public init() {}

    public func add(_ run: AutomationRun) async throws { runStore[run.id] = run }

    public func finish(_ id: UUID, outcome: AutomationRun.Outcome, endedAt: Date, errorDescription: String?) async throws {
        runStore[id]?.outcome = outcome
        runStore[id]?.endedAt = endedAt
        runStore[id]?.errorDescription = errorDescription
    }

    public func runs(for automationName: String, startDate: Date?, endDate: Date?, limit: Int) async throws -> [AutomationRun] {
        Array(runStore.values
            .filter { $0.automationName == automationName && $0.startedAt >= (startDate ?? .distantPast) && $0.startedAt < (endDate ?? .distantFuture) }
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(limit))
    }

    public func latestRuns(since date: Date, limit: Int) async throws -> [AutomationRun] {
        Array(runStore.values.filter { $0.startedAt >= date }.sorted { $0.startedAt > $1.startedAt }.prefix(limit))
    }

    public func latestRunPerAutomation() async throws -> [String: AutomationRun] {
        Dictionary(runStore.values.map { ($0.automationName, $0) }) { $0.startedAt > $1.startedAt ? $0 : $1 }
    }

    public func markRunningAsInterrupted() async throws {
        for (id, run) in runStore where run.outcome == .running {
            runStore[id]?.outcome = .interrupted
        }
    }

    public func addCommand(_ command: ActionLogItem) async throws { commandStore.insert(command, at: 0) }

    public func setCommandStatus(_ id: UUID, to status: ActionLogItem.Status) async throws {
        guard let index = commandStore.firstIndex(where: { $0.id == id }) else { return }
        commandStore[index].status = status
    }

    public func commands(limit: Int?, runId: UUID?) async throws -> [ActionLogItem] {
        let matching = commandStore.filter { runId == nil || $0.runId == runId }
        return limit.map { Array(matching.prefix($0)) } ?? matching
    }

    public func clearCommands() async throws { commandStore.removeAll() }

    public func addPush(_ push: JournalPush) async throws { pushStore.insert(push, at: 0) }

    public func pushes(runId: UUID?) async throws -> [JournalPush] {
        pushStore.filter { runId == nil || $0.runId == runId }
    }

    public func deleteEntries(olderThan date: Date) async throws {
        runStore = runStore.filter { $0.value.startedAt >= date }
        commandStore.removeAll { $0.timestamp < date }
        pushStore.removeAll { $0.timestamp < date }
    }
}

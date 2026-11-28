//
//  Journal.swift
//  HomeAutomationKit
//

import Foundation
import HAModels
import Logging
import Synchronization

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

    /// A write, or the marker `flush` waits for; the marker is its own case so that a dropped one still resumes its caller.
    private enum Item: Sendable {
        case write(@Sendable () async throws -> Void)
        case flush(CheckedContinuation<Void, Never>)
    }

    private let store: any JournalStore
    private let queue: AsyncStream<Item>.Continuation
    /// Writes dropped because the queue was full, and how many were queued at all (for tests).
    private let counters = Mutex((dropped: 0, enqueued: 0))

    public init(store: any JournalStore) {
        self.store = store
        let (stream, queue) = AsyncStream<Item>.makeStream(bufferingPolicy: .bufferingNewest(Self.queueLimit))
        self.queue = queue
        // Normal priority like the persist queue of the `HomeManager`: a background consumer is starved under load.
        Task.detached {
            for await item in stream {
                switch item {
                case .write(let write):
                    do {
                        try await write()
                    } catch {
                        Self.logger.error("Failed to write the journal", metadata: ["error": "\(error)"])
                    }
                case .flush(let continuation):
                    continuation.resume()
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

    /// The newest executed command of every radiator; empty when the database fails.
    public func lastHeatingWrites() async -> [ActionLogItem] {
        do {
            return try await store.lastHeatingWrites()
        } catch {
            Self.logger.error("Failed to read the last heating commands of the journal", metadata: ["error": "\(error)"])
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

    /// Removes entries of every kind older than `date`; the cleanup calls this.
    public func deleteEntries(olderThan date: Date) async throws {
        try await store.deleteEntries(olderThan: date)
    }

    /// Returns once every write queued so far was tried.
    public func flush() async {
        await withCheckedContinuation { continuation in
            enqueue(.flush(continuation))
        }
    }

    /// How many items were queued so far, a dropped one included.
    var enqueuedCount: Int { counters.withLock { $0.enqueued } }

    private func enqueue(_ write: @escaping @Sendable () async throws -> Void) {
        enqueue(.write(write))
    }

    private func enqueue(_ item: Item) {
        counters.withLock { $0.enqueued += 1 }
        switch queue.yield(item) {
        case .dropped(let dropped):
            // The oldest item made room. A dropped flush marker still resumes its caller, so `flush` cannot hang.
            if case .flush(let continuation) = dropped { continuation.resume() }
            let total = counters.withLock { counters in
                counters.dropped += 1
                return counters.dropped
            }
            if total == 1 || total.isMultiple(of: 500) {
                Self.logger.warning("Journal queue full, dropped writes", metadata: ["dropped": "\(total)"])
            }
        case .terminated:
            // Nothing will be written any more: the caller of a flush must not wait for it.
            if case .flush(let continuation) = item { continuation.resume() }
        default:
            break
        }
    }
}

/// Keeps the journal in memory; for tests and previews.
public actor InMemoryJournalStore: JournalStore {
    private var runStore: [UUID: AutomationRun] = [:]
    private var commandStore: [ActionLogItem] = []
    private var pushStore: [JournalPush] = []

    /// - Parameter commands: Rows that are in the store from the start, e.g. seeded radiator commands.
    public init(commands: [ActionLogItem] = []) {
        commandStore = commands
    }

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

    public func heatingWrites(placeId: String, startDate: Date?, endDate: Date?) async throws -> [ActionLogItem] {
        commandStore
            .filter { $0.isExecutedHeatingWrite && $0.entityId.placeId == placeId
                && $0.timestamp >= (startDate ?? .distantPast) && $0.timestamp < (endDate ?? .distantFuture)
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func lastHeatingWrites() async throws -> [ActionLogItem] {
        Dictionary(grouping: commandStore.filter(\.isExecutedHeatingWrite)) { "\($0.entityId.placeId)/\($0.entityId.name)" }
            .compactMap { $0.value.max { $0.timestamp < $1.timestamp } }
    }

    public func addPush(_ push: JournalPush) async throws { pushStore.insert(push, at: 0) }

    public func pushes(runId: UUID?) async throws -> [JournalPush] {
        pushStore.filter { runId == nil || $0.runId == runId }
    }

    public func deleteEntries(olderThan date: Date) async throws {
        runStore = runStore.filter { $0.value.startedAt >= date }
        commandStore.removeAll { $0.timestamp < date && $0.reason == nil }
        pushStore.removeAll { $0.timestamp < date }
    }
}

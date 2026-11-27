//
//  Journal.swift
//  HomeAutomationKit
//

import Foundation

/// The kinds of entry the journal holds, one table with an entry per kind.
public enum JournalKind: String, Sendable, Codable, CaseIterable {
    case run
    case command
    case push
}

/// One push the server handed to the notification adapter.
public struct JournalPush: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    /// The `AutomationRun` that sent the push; `nil` for pushes outside a run.
    public let runId: UUID?
    public let title: String
    public let message: String
    /// The stable push id (`apns-collapse-id`).
    public let pushId: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), runId: UUID?, title: String, message: String, pushId: String) {
        self.id = id
        self.timestamp = timestamp
        self.runId = runId
        self.title = title
        self.message = message
        self.pushId = pushId
    }
}

/// Persistence of the journal: runs, commands and pushes in one table, linked by the run.
/// Implemented by the server's database; the run side is ``AutomationRunRepository``.
public protocol JournalStore: AutomationRunRepository {
    func addCommand(_ command: ActionLogItem) async throws
    func setCommandStatus(_ id: UUID, to status: ActionLogItem.Status) async throws
    /// Newest first.
    func commands(limit: Int?, runId: UUID?) async throws -> [ActionLogItem]
    /// The executed radiator commands (those with a reason) to the radiators of room `placeId` in
    /// `startDate ..< endDate` (open ends allowed), oldest first.
    func heatingCommands(placeId: String, startDate: Date?, endDate: Date?) async throws -> [ActionLogItem]
    /// The newest executed radiator command of every radiator, whatever its characteristic; the server loads them at start.
    func lastHeatingCommands() async throws -> [ActionLogItem]
    /// Removes every command entry.
    func clearCommands() async throws
    func addPush(_ push: JournalPush) async throws
    /// Newest first.
    func pushes(runId: UUID?) async throws -> [JournalPush]
    /// Removes entries of every kind that are older than `date`, except the radiator commands that carry a
    /// heating reason: those are kept for good, so the last command of every radiator survives any cleanup.
    func deleteEntries(olderThan date: Date) async throws
}

public extension JournalStore {
    /// A store that does not keep radiator commands answers none.
    func heatingCommands(placeId: String, startDate: Date?, endDate: Date?) async throws -> [ActionLogItem] { [] }
    func lastHeatingCommands() async throws -> [ActionLogItem] { [] }
}

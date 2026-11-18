//
//  AutomationRun.swift
//  HAModels
//

import Foundation

/// One execution of an automation: what triggered it, when it ran and how it ended.
public struct AutomationRun: Identifiable, Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable, CaseIterable {
        case running
        case completed
        /// A newer trigger of the same automation replaced this run.
        case superseded
        /// Stopped via the API.
        case stopped
        case failed
        /// The server restarted while the run was in progress.
        case interrupted
    }

    public let id: UUID
    public let automationName: String
    public let startedAt: Date
    public var endedAt: Date?
    public let trigger: AutomationTrigger
    public var outcome: Outcome
    public var errorDescription: String?

    public init(id: UUID = UUID(), automationName: String, startedAt: Date, endedAt: Date? = nil, trigger: AutomationTrigger, outcome: Outcome, errorDescription: String? = nil) {
        self.id = id
        self.automationName = automationName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.trigger = trigger
        self.outcome = outcome
        self.errorDescription = errorDescription
    }
}

/// The `HomeEvent` that started an `AutomationRun`, reduced to what a person needs to read.
public struct AutomationTrigger: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case entityChange
        case time
        case sunrise
        case sunset
    }

    public let kind: Kind
    public let entityId: EntityId?
    public let summary: String

    public init(kind: Kind, entityId: EntityId?, summary: String) {
        self.kind = kind
        self.entityId = entityId
        self.summary = summary
    }

    public func appending(_ detail: String) -> Self {
        Self(kind: kind, entityId: entityId, summary: "\(summary) · \(detail)")
    }
}

extension HomeEvent {
    public var trigger: AutomationTrigger {
        switch self {
        case .change(let item):
            let summary = "\(EntityHistoryItem(item).valueDescription) · \(item.entityId.name) (\(item.entityId.placeId))"
            return AutomationTrigger(kind: .entityChange, entityId: item.entityId, summary: summary)
        case .time(let date):
            return AutomationTrigger(kind: .time, entityId: nil, summary: "Schedule \(date.formatted(date: .omitted, time: .shortened))")
        case .sunrise:
            return AutomationTrigger(kind: .sunrise, entityId: nil, summary: "Sunrise")
        case .sunset:
            return AutomationTrigger(kind: .sunset, entityId: nil, summary: "Sunset")
        }
    }
}

/// Persistence of `AutomationRun`s; implemented by the server's database.
public protocol AutomationRunRepository: Sendable {
    func add(_ run: AutomationRun) async throws
    func finish(_ id: UUID, outcome: AutomationRun.Outcome, endedAt: Date, errorDescription: String?) async throws
    /// Newest first.
    func runs(for automationName: String, startDate: Date?, endDate: Date?, limit: Int) async throws -> [AutomationRun]
    /// Newest first, across all automations.
    func latestRuns(since date: Date, limit: Int) async throws -> [AutomationRun]
    /// Keyed by automation name.
    func latestRunPerAutomation() async throws -> [String: AutomationRun]
    func markRunningAsInterrupted() async throws
    func deleteRuns(olderThan date: Date) async throws
}

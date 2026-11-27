//
//  DatabaseCleanup.swift
//

import Foundation
import HAModels

/// The database upkeep as an automation, so its runs show in the Automationen tab and it can be switched off
/// there. It runs once after a server start and then on the clock: the rollup every hour, the cleanup and the
/// journal cleanup daily.
/// A trigger while a run is still going does not cut that run.
///
/// What the steps delete and keep is decided by the server behind ``HomeManagable/performStorageUpkeep(_:now:)``.
public struct DatabaseCleanup: Automatable {
    public static let defaultName = "DatabaseCleanup"
    /// The hour of the day (server time) of the daily cleanup.
    public static let cleanupHour = 3

    public var isActive = true
    public let name: String
    public private(set) var triggerEntityIds = Set<EntityId>()
    public var supersedesRunningRun: Bool { false }

    public init(_ name: String = DatabaseCleanup.defaultName) {
        self.name = name
    }

    /// The steps an event asks for; none when the event is no cadence of the upkeep.
    public static func steps(for event: HomeEvent, calendar: Calendar = .current) -> [StorageUpkeepStep] {
        switch event {
        case .serverStarted:
            return StorageUpkeepStep.allCases
        case .time(let date):
            guard calendar.component(.minute, from: date) == 0 else { return [] }
            return calendar.component(.hour, from: date) == cleanupHour ? [.rollup, .cleanup, .journal] : [.rollup]
        default:
            return []
        }
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        !Self.steps(for: event).isEmpty
    }

    public func triggerSummary(for event: HomeEvent, using hm: HomeManagable) async -> String? {
        Self.steps(for: event).map(\.rawValue).joined(separator: ", ")
    }

    public func execute(using hm: HomeManagable) async throws {
        let steps = AutomationRunContext.event.map { Self.steps(for: $0) } ?? StorageUpkeepStep.allCases
        let now = Date()
        var firstError: (any Error)?
        for step in steps {
            do {
                try await hm.performStorageUpkeep(step, now: now)
            } catch {
                log.error("Database upkeep step \(step.rawValue) failed: \(error)")
                firstError = firstError ?? error
            }
        }
        if let firstError { throw firstError }
    }
}

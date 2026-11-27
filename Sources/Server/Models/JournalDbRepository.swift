//
//  JournalDbRepository.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAModels

struct JournalDbRepository: JournalStore {
    /// Resolved per query, see `EntityStorageDbRepository.database`.
    let database: @Sendable () -> any Database

    private func entries(_ kind: JournalKind) -> QueryBuilder<JournalDbItem> {
        JournalDbItem.query(on: database()).filter(\.$kind == kind.rawValue)
    }

    // MARK: - runs

    func add(_ run: AutomationRun) async throws {
        try await JournalDbItem(run).create(on: database())
    }

    func finish(_ id: UUID, outcome: AutomationRun.Outcome, endedAt: Date, errorDescription: String?) async throws {
        try await entries(.run)
            .filter(\.$id == id)
            .set(\.$outcome, to: outcome.rawValue)
            .set(\.$endedAt, to: endedAt)
            .set(\.$errorDescription, to: errorDescription)
            .update()
    }

    func runs(for automationName: String, startDate: Date?, endDate: Date?, limit: Int) async throws -> [AutomationRun] {
        var query = entries(.run).filter(\.$title == automationName)
        if let startDate {
            query = query.filter(\.$timestamp >= startDate)
        }
        if let endDate {
            query = query.filter(\.$timestamp < endDate)
        }
        return try await query
            .sort(\.$timestamp, .descending)
            .limit(limit)
            .all()
            .map { try $0.toRun() }
    }

    func latestRuns(since date: Date, limit: Int) async throws -> [AutomationRun] {
        try await entries(.run)
            .filter(\.$timestamp >= date)
            .sort(\.$timestamp, .descending)
            .limit(limit)
            .all()
            .map { try $0.toRun() }
    }

    func latestRunPerAutomation() async throws -> [String: AutomationRun] {
        let names = try await entries(.run).unique().all(\.$title)
        var result: [String: AutomationRun] = [:]
        for name in names {
            result[name] = try await runs(for: name, startDate: nil, endDate: nil, limit: 1).first
        }
        return result
    }

    func markRunningAsInterrupted() async throws {
        try await entries(.run)
            .filter(\.$outcome == AutomationRun.Outcome.running.rawValue)
            .set(\.$outcome, to: AutomationRun.Outcome.interrupted.rawValue)
            .update()
    }

    // MARK: - commands

    func addCommand(_ command: ActionLogItem) async throws {
        try await JournalDbItem(command).create(on: database())
    }

    func setCommandStatus(_ id: UUID, to status: ActionLogItem.Status) async throws {
        try await entries(.command)
            .filter(\.$id == id)
            .set(\.$status, to: status.rawValue)
            .update()
    }

    func commands(limit: Int?, runId: UUID?) async throws -> [ActionLogItem] {
        var query = entries(.command)
        if let runId {
            query = query.filter(\.$runId == runId)
        }
        query = query.sort(\.$timestamp, .descending)
        if let limit {
            query = query.limit(limit)
        }
        return try await query.all().map { try $0.toCommand() }
    }

    func clearCommands() async throws {
        try await entries(.command).delete()
    }

    // MARK: - pushes

    func addPush(_ push: JournalPush) async throws {
        try await JournalDbItem(push).create(on: database())
    }

    func pushes(runId: UUID?) async throws -> [JournalPush] {
        var query = entries(.push)
        if let runId {
            query = query.filter(\.$runId == runId)
        }
        return try await query.sort(\.$timestamp, .descending).all().map { try $0.toPush() }
    }

    // MARK: - cleanup

    func deleteEntries(olderThan date: Date) async throws {
        try await JournalDbItem.query(on: database())
            .filter(\.$timestamp < date)
            .delete()
    }
}

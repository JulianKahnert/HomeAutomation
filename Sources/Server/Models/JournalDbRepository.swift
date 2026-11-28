//
//  JournalDbRepository.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAModels
import SQLKit
import Vapor

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

    func heatingWrites(placeId: String, startDate: Date?, endDate: Date?) async throws -> [ActionLogItem] {
        var query = entries(.command)
            .filter(\.$entityPlaceId == placeId)
            .filter(\.$reason != nil)
            .filter(\.$commandValue != nil)
            .filter(\.$status == ActionLogItem.Status.executed.rawValue)
        if let startDate {
            query = query.filter(\.$timestamp >= startDate)
        }
        if let endDate {
            query = query.filter(\.$timestamp < endDate)
        }
        return try await query.sort(\.$timestamp, .ascending).all().map { try $0.toCommand() }
    }

    func lastHeatingWrites() async throws -> [ActionLogItem] {
        let radiators = try await entries(.command)
            .filter(\.$reason != nil)
            .filter(\.$commandValue != nil)
            .filter(\.$status == ActionLogItem.Status.executed.rawValue)
            .field(\.$entityPlaceId)
            .field(\.$entityName)
            .unique()
            .all()
        var commands: [ActionLogItem] = []
        for radiator in radiators {
            guard let placeId = radiator.entityPlaceId, let name = radiator.entityName else { continue }
            let last = try await entries(.command)
                .filter(\.$entityPlaceId == placeId)
                .filter(\.$entityName == name)
                .filter(\.$reason != nil)
                .filter(\.$commandValue != nil)
                .filter(\.$status == ActionLogItem.Status.executed.rawValue)
                .sort(\.$timestamp, .descending)
                .first()
            if let last { commands.append(try last.toCommand()) }
        }
        return commands
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

    /// Command entries with a heating reason stay for good (the last command of every radiator survives).
    /// One batched delete per kind, each an exact range on `idx_journal_kind_timestamp`: a statement locks only its
    /// batch, and no statement scans the whole table.
    func deleteEntries(olderThan date: Date) async throws {
        guard let sql = database() as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL queries")
        }
        let kinds: [(kind: JournalKind, onlyWithoutReason: Bool)] = [(.run, false), (.push, false), (.command, true)]
        for (kind, onlyWithoutReason) in kinds {
            // The probe carries the same filter, so the heating commands that stay do not keep the loop running.
            let reasonFilter: SQLQueryString = onlyWithoutReason ? " AND \(ident: "reason") IS NULL" : ""
            while true {
                try await sql.raw("""
                    DELETE FROM \(ident: JournalDbItem.schema)
                    WHERE \(ident: "kind") = \(bind: kind.rawValue) AND \(ident: "timestamp") < \(bind: date)\(reasonFilter)
                    ORDER BY \(ident: "timestamp") LIMIT \(literal: Self.deleteBatchSize)
                    """)
                    .run()
                let left = try await sql.raw("""
                    SELECT 1 AS \(ident: "found") FROM \(ident: JournalDbItem.schema)
                    WHERE \(ident: "kind") = \(bind: kind.rawValue) AND \(ident: "timestamp") < \(bind: date)\(reasonFilter) LIMIT 1
                    """)
                    .first()
                if left == nil { break }
            }
        }
    }

    static let deleteBatchSize = 5_000
}

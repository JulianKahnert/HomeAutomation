//
//  AutomationRunDbRepository.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAModels

struct AutomationRunDbRepository: AutomationRunRepository {
    let database: any Database

    func add(_ run: AutomationRun) async throws {
        try await AutomationRunDbItem(run).create(on: database)
    }

    func finish(_ id: UUID, outcome: AutomationRun.Outcome, endedAt: Date, errorDescription: String?) async throws {
        try await AutomationRunDbItem.query(on: database)
            .filter(\.$id == id)
            .set(\.$outcome, to: outcome.rawValue)
            .set(\.$endedAt, to: endedAt)
            .set(\.$errorDescription, to: errorDescription)
            .update()
    }

    func runs(for automationName: String, startDate: Date?, endDate: Date?, limit: Int) async throws -> [AutomationRun] {
        var query = AutomationRunDbItem.query(on: database)
            .filter(\.$automationName == automationName)
        if let startDate {
            query = query.filter(\.$startedAt >= startDate)
        }
        if let endDate {
            query = query.filter(\.$startedAt < endDate)
        }
        return try await query
            .sort(\.$startedAt, .descending)
            .limit(limit)
            .all()
            .map { try $0.toRun() }
    }

    func latestRuns(since date: Date, limit: Int) async throws -> [AutomationRun] {
        try await AutomationRunDbItem.query(on: database)
            .filter(\.$startedAt >= date)
            .sort(\.$startedAt, .descending)
            .limit(limit)
            .all()
            .map { try $0.toRun() }
    }

    func latestRunPerAutomation() async throws -> [String: AutomationRun] {
        let names = try await AutomationRunDbItem.query(on: database).unique().all(\.$automationName)
        var result: [String: AutomationRun] = [:]
        for name in names {
            result[name] = try await runs(for: name, startDate: nil, endDate: nil, limit: 1).first
        }
        return result
    }

    func markRunningAsInterrupted() async throws {
        try await AutomationRunDbItem.query(on: database)
            .filter(\.$outcome == AutomationRun.Outcome.running.rawValue)
            .set(\.$outcome, to: AutomationRun.Outcome.interrupted.rawValue)
            .update()
    }

    func deleteRuns(olderThan date: Date) async throws {
        try await AutomationRunDbItem.query(on: database)
            .filter(\.$startedAt < date)
            .delete()
    }
}

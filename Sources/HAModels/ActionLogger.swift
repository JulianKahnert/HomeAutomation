//
//  ActionLogger.swift
//  HAModels
//
//  Created by Julian Kahnert on 14.11.25.
//

import Foundation

public actor ActionLogger {
    public static let shared = ActionLogger()

    public static let maxEntries = 1000

    private var actions: [ActionLogItem] = []

    private init() {}

    public func log(
        action: HomeManagableAction,
        hasCacheHit: Bool
    ) {
        let item = ActionLogItem(
            action: action,
            hasCacheHit: hasCacheHit
        )

        // Insert at beginning (newest first)
        actions.insert(item, at: 0)

        // Trim to max entries
        if actions.count > Self.maxEntries {
            actions = Array(actions.prefix(Self.maxEntries))
        }
    }

    public func getActions(limit: Int? = nil) -> [ActionLogItem] {
        var result = actions

        // Apply limit if provided
        if let limit = limit {
            let cappedLimit = min(limit, Self.maxEntries)
            result = Array(result.prefix(cappedLimit))
        }

        return result
    }

    public func exportAsText() -> String {
        let header = """
        HomeKit Action Log
        Exported: \(Date().formatted(date: .long, time: .standard))
        Total Actions: \(actions.count)
        =====================================

        """

        let entries = actions.map { item in
            let status = item.hasCacheHit ? "✅ Cached" : "🆕 Fresh (no cache hit)"
            return """
            [\(item.timestamp.formatted(date: .numeric, time: .standard))] \(item.displayName)
            Action: \(item.detailDescription)
            Entity: \(item.action.entityId)
            Status: \(status)

            """
        }.joined(separator: "\n")

        return header + entries
    }

    public func clear() {
        actions.removeAll()
    }
}

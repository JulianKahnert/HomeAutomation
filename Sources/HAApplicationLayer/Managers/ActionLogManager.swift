//
//  ActionLogManager.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 14.11.25.
//

import HAModels

public actor ActionLogManager {
    public static let maxEntries = 1000

    private var actions: [ActionLogItem] = []

    public init() {}

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

    public func clear() {
        actions.removeAll()
    }
}

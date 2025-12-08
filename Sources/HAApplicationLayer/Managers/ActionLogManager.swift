//
//  ActionLogManager.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 14.11.25.
//

import HAModels
import Shared

public actor ActionLogManager {
    public static let maxEntries = 1000

    private var actions: [ActionLogItem] = []
    private let commandCache = Cache<String, HomeManagableAction>(entryLifetime: .minutes(2))

    public init() {}

    /// Log an action and check if it was a duplicate (cache hit)
    /// - Parameter action: The action to log
    /// - Returns: true if this was a duplicate action (cache hit), false if it's a new action that should be executed
    public func log(action: HomeManagableAction) async -> Bool {
        let cacheKey = "\(action.entityId)-\(action.actionName)"

        // Check if action is in cache
        let hasCacheHit: Bool
        if let cachedAction = await commandCache.value(forKey: cacheKey) {
            // Compare the cached action with the current action
            // If they are the same (including values), it's a cache hit
            hasCacheHit = (cachedAction == action)
        } else {
            hasCacheHit = false
        }

        // If not a cache hit, mark command as executed
        if !hasCacheHit {
            await commandCache.insert(action, forKey: cacheKey)
        }

        // Log the action
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

        return hasCacheHit
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

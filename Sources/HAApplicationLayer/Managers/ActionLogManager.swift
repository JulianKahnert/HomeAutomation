//
//  ActionLogManager.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 14.11.25.
//

import Foundation
import HAModels
import Shared

public actor ActionLogManager {
    public static let maxEntries = 1000

    private var actions: [ActionLogItem] = []
    private let commandCache: Cache<String, HomeManagableAction>
    /// Maps an entity to the set of cache keys (`"<entityId>-<actionName>"`) currently cached for it.
    /// `NSCache` cannot enumerate its keys, so this index lets us find an entity's cached commands
    /// when a state change arrives. It self-heals: keys whose cache entry has expired are pruned
    /// the next time the entity is visited in `invalidateContradictedCommands(for:)`.
    private var keysByEntity: [EntityId: Set<String>] = [:]

    public init(dateProvider: @escaping @Sendable () -> Date = Date.init) {
        self.commandCache = Cache(dateProvider: dateProvider, entryLifetime: .minutes(2))
    }

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
            keysByEntity[action.entityId, default: []].insert(cacheKey)
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

    /// Reset cached commands for `item.entityId` that the freshly observed device state contradicts.
    ///
    /// This lets the automation engine re-issue a command after the device has drifted away from
    /// what the server commanded — for example when a scene was activated outside the server, or a
    /// device was changed manually. It is safe to call on every incoming state change: a state that
    /// *confirms* the last command (the command's own echo) is not contradicted, so it is never
    /// invalidated and command deduplication is preserved.
    ///
    /// - Parameter item: A freshly observed entity state.
    /// - Returns: The actions that were invalidated (for logging / observability).
    @discardableResult
    public func invalidateContradictedCommands(for item: EntityStorageItem) async -> [HomeManagableAction] {
        guard let keys = keysByEntity[item.entityId], !keys.isEmpty else { return [] }

        var invalidatedActions: [HomeManagableAction] = []
        var deadKeys: Set<String> = []

        for key in keys {
            guard let cachedAction = await commandCache.value(forKey: key) else {
                // The cache entry expired or was evicted — drop the stale index entry.
                deadKeys.insert(key)
                continue
            }
            if cachedAction.isContradicted(by: item) {
                await commandCache.removeValue(forKey: key)
                deadKeys.insert(key)
                invalidatedActions.append(cachedAction)
            }
        }

        if !deadKeys.isEmpty {
            keysByEntity[item.entityId]?.subtract(deadKeys)
            if keysByEntity[item.entityId]?.isEmpty == true {
                keysByEntity[item.entityId] = nil
            }
        }

        return invalidatedActions
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

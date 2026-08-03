//
//  ActionLogManager.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 14.11.25.
//

import Foundation
import HAModels
import Shared

/// Identifies a cached command: one entry per `(entity, action kind)`. Typed instead of the former
/// `"<entityId>-<actionName>"` string so the key cannot collide and carries its `entityId` for
/// per-entity lookups during `invalidateContradictedCommands(for:)`.
private struct CommandCacheKey: Hashable, Sendable {
    let entityId: EntityId
    let actionName: String

    init(_ action: HomeManagableAction) {
        self.entityId = action.entityId
        self.actionName = action.actionName
    }
}

public actor ActionLogManager {
    public static let maxEntries = 1000

    private var actions: [ActionLogItem] = []
    private let commandCache: Cache<CommandCacheKey, HomeManagableAction>

    public init(dateProvider: @escaping @Sendable () -> Date = Date.init) {
        self.commandCache = Cache(dateProvider: dateProvider, entryLifetime: .minutes(2))
    }

    /// Log an action and check if it was a duplicate (cache hit)
    ///
    /// Logging alone does not deduplicate the action: only `markExecuted(_:)` does. A command that
    /// never reached the device (cancelled, adapter error) must stay a cache miss so the next
    /// attempt is allowed through.
    ///
    /// - Parameter action: The action to log
    /// - Returns: true if this was a duplicate action (cache hit), false if it's a new action that should be executed
    public func log(action: HomeManagableAction) async -> Bool {
        let cacheKey = CommandCacheKey(action)

        // Check if action is in cache
        let hasCacheHit: Bool
        if let cachedAction = await commandCache.value(forKey: cacheKey) {
            // Compare the cached action with the current action
            // If they are the same (including values), it's a cache hit
            hasCacheHit = (cachedAction == action)
        } else {
            hasCacheHit = false
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

    /// Mark an action as executed so identical follow-up commands are deduplicated for the cache's
    /// lifetime.
    ///
    /// Must only be called once the command actually reached the device — see `log(action:)`.
    ///
    /// - Parameter action: The action that was successfully performed.
    public func markExecuted(_ action: HomeManagableAction) async {
        await commandCache.insert(action, forKey: CommandCacheKey(action))
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
        var invalidatedActions: [HomeManagableAction] = []

        // The cache prunes its own key index on expiry/eviction (a missing entry just yields `nil`).
        for key in await commandCache.keys where key.entityId == item.entityId {
            guard let cachedAction = await commandCache.value(forKey: key) else { continue }
            if cachedAction.isContradicted(by: item) {
                await commandCache.removeValue(forKey: key)
                invalidatedActions.append(cachedAction)
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

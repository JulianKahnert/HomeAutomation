//
//  CommandCache.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 14.11.25.
//

import Foundation
import HAModels
import Shared

/// Identifies a cached command: one entry per `(entity, action kind)`.
private struct CommandCacheKey: Hashable, Sendable {
    let entityId: EntityId
    let actionName: String

    init(_ action: HomeManagableAction) {
        self.entityId = action.entityId
        self.actionName = action.actionName
    }
}

/// Remembers the commands that reached a device, so an identical follow-up is skipped. What was
/// commanded is recorded in the ``Journal``, not here.
public actor CommandCache {
    private let cache: Cache<CommandCacheKey, HomeManagableAction>

    public init(dateProvider: @escaping @Sendable () -> Date = Date.init) {
        self.cache = Cache(dateProvider: dateProvider, entryLifetime: .minutes(2))
    }

    /// Whether `action` repeats a command that already reached its device.
    ///
    /// Asking does not remember the action: only `markExecuted(_:)` does. A command that never reached
    /// the device (cancelled, adapter error) must stay a miss so the next attempt is allowed through.
    public func isDuplicate(_ action: HomeManagableAction) async -> Bool {
        guard let cachedAction = await cache.value(forKey: CommandCacheKey(action)) else { return false }
        return cachedAction == action
    }

    /// Must only be called once the command actually reached the device. The entity has one state, so this
    /// replaces any cached command of the same entity (`turnOn` replaces `turnOff`).
    public func markExecuted(_ action: HomeManagableAction) async {
        await forget(action.entityId)
        await cache.insert(action, forKey: CommandCacheKey(action))
    }

    /// Drops every cached command of `entityId`.
    public func forget(_ entityId: EntityId) async {
        for key in await cache.keys where key.entityId == entityId {
            await cache.removeValue(forKey: key)
        }
    }

    /// Reset cached commands for `item.entityId` that the freshly observed device state contradicts.
    ///
    /// This lets the automation engine re-issue a command after the device has drifted away from
    /// what the server commanded. A state that *confirms* the last command (its own echo) is not
    /// contradicted, so command deduplication is preserved.
    ///
    /// - Returns: The actions that were invalidated (for logging / observability).
    @discardableResult
    public func invalidateContradictedCommands(for item: EntityStorageItem) async -> [HomeManagableAction] {
        var invalidatedActions: [HomeManagableAction] = []
        for key in await cache.keys where key.entityId == item.entityId {
            guard let cachedAction = await cache.value(forKey: key) else { continue }
            if cachedAction.isContradicted(by: item) {
                await cache.removeValue(forKey: key)
                invalidatedActions.append(cachedAction)
            }
        }
        return invalidatedActions
    }
}

//
//  HomeManager.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
import HAModels
import Logging
import Shared

@HomeManagerActor
public final class HomeManager: HomeManagable {
    /// Number of times a command is sent to the adapter before it is dropped.
    nonisolated private static let maxAttempts = 3

    private let log = Logger(label: "HomeManager")
    private let windowManager: WindowManager
    private let actionLogManager: ActionLogManager

    private let getAdapter: () async -> (any EntityAdapterable)?
    private let location: Location
    private let storageRepo: StorageRepository
    private let notificationSender: NotificationSender
    private let entityCache = Cache<EntityId, EntityStorageItem>(entryLifetime: .hours(2))
    /// One retry slot per entity: a newer failed action replaces an older queued one, so the newest
    /// intent wins. `EntityId` carries the characteristic, so a lamp's brightness and color
    /// temperature occupy separate slots; `turnOn` and `turnOff` share the switcher slot on purpose —
    /// replaying both would be contradictory.
    private var failedActions: [EntityId: (action: HomeManagableAction, attempt: Int)] = [:]

    /// - Parameter retryTicks: Cadence at which queued failed actions are retried. Pass a stream to
    ///   drive the retries deterministically; the default is a 5s timer.
    public init(getAdapter: @escaping () async -> (any EntityAdapterable)?, storageRepo: StorageRepository, notificationSender: NotificationSender, location: Location, actionLogManager: ActionLogManager, retryTicks: AsyncStream<Void>? = nil) {
        self.windowManager = WindowManager(notificationSender: notificationSender)
        self.actionLogManager = actionLogManager
        self.getAdapter = getAdapter
        self.storageRepo = storageRepo
        self.notificationSender = notificationSender
        self.location = location

//        Task {
//            let adapter = await getAdapter()
//            let entityStream = await adapter.getEntityStream()
//            for await entityStorageItem in entityStream {
//                self.log.info("Received storage item \(entityStorageItem)")
//                await self.addEntityHistory(entityStorageItem)
//                self.entityStreamContinuation.yield(entityStorageItem.entityId)
//            }
//        }

        let ticks = retryTicks ?? Self.timerRetryTicks()
        Task.detached(priority: .low) {
            for await _ in ticks {
                let queued = await self.popAllFailedActions()
                for (action, attempt) in queued {
                    self.log.debug("Performing failed action again: \(action) [attempt \(attempt + 1)/\(Self.maxAttempts)]")
                    await self.perform(action, attempt: attempt)
                }
            }
        }
    }

    /// Production retry cadence: a tick every 5s (the shared timer aligns its first tick to the next
    /// minute boundary).
    private static func timerRetryTicks() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        Task.detached(priority: .low) {
            for await _ in Timer.publish(every: .seconds(5)) {
                continuation.yield(())
            }
            continuation.finish()
        }
        return stream
    }

    public func getCurrentEntity(with entityId: EntityId) async throws -> EntityStorageItem {
        if let item = await entityCache.value(forKey: entityId) {
            return item
        }
        return try await storageRepo.getCurrent(entityId).get(with: log)
    }

    public func getPreviousEntity(with entityId: EntityId) async throws -> EntityStorageItem? {
        return try await storageRepo.getPrevious(entityId).get(with: log)
    }

    public func getAllEntitiesLive() async throws -> [EntityStorageItem] {
        log.info("getAllEntitiesLive() — starting distributed actor call")
        let start = ContinuousClock.now
        let entities = try await getAdapter().get(with: log).getAllEntitiesLive()
        let duration = start.duration(to: .now)
        log.info("getAllEntitiesLive() — returned \(entities.count) entities in \(duration)")
        return entities
    }

    public func findEntity(_ entityId: EntityId) async throws {
        guard await entityCache.value(forKey: entityId) == nil else {
            // found item in cache
            return
        }
        return try await getAdapter().get(with: log).findEntity(entityId)
    }

    public func perform(_ action: HomeManagableAction) async {
        // Round values to prevent excessive HomeKit updates
        let roundedAction = action.rounded()
        await perform(roundedAction, attempt: 0)
    }

    private func perform(_ action: HomeManagableAction, attempt: Int) async {
        // Cancellation is honoured at command boundaries only: a superseded automation run must not
        // start further commands, but a command that already started always runs to completion (see
        // the shield below). Checked before logging so a skipped command produces no log entry.
        guard !Task.isCancelled else {
            log.debug("Skipping action of a cancelled run: [\(action)]")
            return
        }

        // Log action and check if it's a duplicate (cache hit)
        let hasCacheHit = await actionLogManager.log(action: action)

        if hasCacheHit {
            log.info("Skipping duplicate command: [\(action)]")
            return
        }

        // Not a cache hit - execute the action
        log.debug("Executing action: [\(action)]")

        do {
            let adapter = try await getAdapter().get(with: log)

            // Shield the in-flight command from the caller's cancellation: an unstructured task
            // inherits priority, task locals and actor isolation but not cancellation, so a
            // cancelled run can no longer abort the remote call mid-flight and leave a device half
            // configured. The remote call brings its own timeout, so this cannot hang forever.
            let command = Task { try await adapter.perform(action) }
            try await command.value

            // Only a command that reached the device may deduplicate its successors.
            await actionLogManager.markExecuted(action)
        } catch {
            let entityId = action.entityId

            if let entity = try? await getCurrentEntity(with: entityId) {
                log.error("(\(entityId)) entity \(entity)")
            }
            log.error("(\(entityId)) Failed to perform action [\(action), attempt: \(attempt + 1)/\(Self.maxAttempts)]\n\(error)")

            let nextAttempt = attempt + 1
            if nextAttempt < Self.maxAttempts {
                failedActions[entityId] = (action, nextAttempt)
            } else {
                log.critical("Giving up on action [\(action)] after \(Self.maxAttempts) attempts")
            }
        }
    }

    public func trigger(scene sceneName: String) async {
        // No explicit cache reset here: executing a scene changes the affected devices, and those
        // per-characteristic changes echo back through the adapter into `addEntityHistory`, where
        // `invalidateContradictedCommands(for:)` resets any cached command they contradict. This is
        // the same path that handles scenes activated from outside the server, so both are covered
        // uniformly without the server needing to know a scene's entity membership.
        log.info("Triggering scene '\(sceneName)' — starting distributed actor call")
        let start = ContinuousClock.now
        do {
            try await getAdapter().get(with: log).trigger(scene: sceneName)
            let duration = start.duration(to: .now)
            log.info("Triggering scene '\(sceneName)' — completed in \(duration)")
        } catch {
            let duration = start.duration(to: .now)
            log.error("Failed to trigger scene '\(sceneName)' after \(duration)\n\(error)")
        }
    }

    public func addEntityHistory(_ item: EntityStorageItem) async {
        log.debug("Adding entity item to storage \(item.entityId)")
        await entityCache.insert(item, forKey: item.entityId)

        // A freshly observed state can reveal that the device drifted away from what the server last
        // commanded — e.g. a scene activated outside the server (HomeKit only surfaces scenes as the
        // per-characteristic changes they produce, which arrive here), or a manual change. Reset any
        // cached command this state contradicts so the automation engine — which re-evaluates this
        // same event right after — is allowed to re-issue it. A state that confirms the command (the
        // command's own echo) is not contradicted, so deduplication is preserved and no command loop
        // occurs. Done synchronously here so the cache is already reset before the automation runs.
        let invalidatedActions = await actionLogManager.invalidateContradictedCommands(for: item)
        if !invalidatedActions.isEmpty {
            log.info("Invalidated \(invalidatedActions.count) cached command(s) for \(item.entityId) due to state drift: \(invalidatedActions)")
        }

        // Persist item in the background to avoid blocking automation execution
        Task.detached(priority: .background) {
            do {
                if var currentItem = try await self.storageRepo.getCurrent(item.entityId) {

                    // found current item, save it when a change has happend
                    // we want to exclude the timestamp from the equality comparison, so change the timestamp temporarily
                    currentItem.timestamp = item.timestamp
                    guard item != currentItem else { return }

                    try await self.storageRepo.add(item)
                } else {
                    // no current item found add it to the store directly
                    try await self.storageRepo.add(item)
                }
            } catch {
                self.log.critical("Failed to persist entity item \(error)")
            }
        }
    }

    public func maintenance() async throws {
        // delete storage entries older than 2 days
        let date = Date().addingTimeInterval(-1 * 2 * 24 * 60 * 60)
        try await storageRepo.deleteEntries(olderThan: date)
    }

    public func deleteStorageEntries(olderThan date: Date) async throws {
        try await storageRepo.deleteEntries(olderThan: date)
    }

    public func getLocation() -> Location {
        return location
    }

    public func sendNotification(title: String, message: String, id: String) async {
        do {
            log.debug("Sending notification \(title): \(message) [id: \(id)]")
            try await notificationSender.sendNotification(title: title, message: message, id: id)
        } catch {
            log.warning("Failed to send notification: \(error)")
        }
    }

    public func clearWindowNotification(entityId: EntityId) async {
        do {
            let id = entityId.windowNotificationId
            log.debug("Clearing window notification [id: \(id)]")
            try await notificationSender.clearNotification(id: id)
        } catch {
            log.warning("Failed to clear window notification: \(error)")
        }
    }

    public func getWindowStates() async -> [WindowOpenState] {
        await windowManager.getWindowStates()
    }

    public func setWindowOpenState(entityId: EntityId, to state: WindowOpenState?) async {
        await windowManager.setWindowOpenState(entityId: entityId, to: state)
    }

    public func getActionLog(limit: Int?) async -> [ActionLogItem] {
        await actionLogManager.getActions(limit: limit)
    }

    public func clearActionLog() async {
        await actionLogManager.clear()
    }

    private func popAllFailedActions() -> [(action: HomeManagableAction, attempt: Int)] {
        let queued = Array(failedActions.values)
        failedActions.removeAll()
        return queued
    }
}

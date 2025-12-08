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
    nonisolated private static let maxWindowOpenDuration = Duration.minutes(15).timeInterval
    private let log = Logger(label: "HomeManager")
    private let windowManager: WindowManager
    private let actionLogManager: ActionLogManager

    private let getAdapter: () async -> (any EntityAdapterable)?
    private let location: Location
    private let storageRepo: StorageRepository
    private let notificationSender: NotificationSender
    private let entityCache = Cache<EntityId, EntityStorageItem>(entryLifetime: .hours(2))
    private var failedActions: [EntityId: HomeManagableAction] = [:]

    public init(getAdapter: @escaping () async -> (any EntityAdapterable)?, storageRepo: StorageRepository, notificationSender: NotificationSender, location: Location, actionLogManager: ActionLogManager) {
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

        Task.detached(priority: .low) {
            for await _ in Timer.publish(every: .seconds(5)) {
                let actions = await self.popAllFailedActions()
                for action in actions {
                    self.log.debug("Performing failed action again: \(action)")
                    // skip adding this action again after a failed run
                    await self.perform(action, addToFaliedActions: false)
                }
            }
        }
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
        return try await getAdapter().get(with: log).getAllEntitiesLive()
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
        // add errors to failed action in this first run from external source
        await perform(roundedAction, addToFaliedActions: true)
    }

    private func perform(_ action: HomeManagableAction, addToFaliedActions: Bool) async {
        // Log action and check if it's a duplicate (cache hit)
        let hasCacheHit = await actionLogManager.log(action: action)

        if hasCacheHit {
            log.info("Skipping duplicate command: [\(action)]")
            return
        }

        // Not a cache hit - execute the action
        log.debug("Executing action: [\(action)]")

        do {
            try await getAdapter().get(with: log).perform(action)
        } catch {
            let entityId = action.entityId

            if let entity = try? await getCurrentEntity(with: entityId) {
                log.critical("(\(entityId)) entity \(entity)")
            }
            log.critical("(\(entityId)) Failed to perform action [\(action), addToFaliedActions: \(addToFaliedActions)]\n\(error)")

            if addToFaliedActions {
                failedActions[entityId] = action
            }
        }
    }

    public func trigger(scene sceneName: String) async {
        do {
            try await getAdapter().get(with: log).trigger(scene: sceneName)
        } catch {
            log.critical("Failed to trigger scene [\(sceneName)]\n\(error)")
        }
    }

    public func addEntityHistory(_ item: EntityStorageItem) async {
        log.debug("Adding entity item to storage \(item.entityId)")
        await entityCache.insert(item, forKey: item.entityId)

        // persist item in the background, e.g. don't block automation execution
        Task.detached(priority: .background) {

            // update window state
            if let isContactOpen = item.isContactOpen {
                var windowOpenState: WindowOpenState?
                if isContactOpen {
                    let name = "\(item.entityId.name) (\(item.entityId.placeId))"
                    windowOpenState = WindowOpenState(name: name, opened: Date(), maxOpenDuration: Self.maxWindowOpenDuration)
                }
                await self.windowManager.setWindowOpenState(entityId: item.entityId, to: windowOpenState)
            }

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
                assertionFailure()
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

    public func sendNotification(title: String, message: String) async {
        do {
            log.debug("Sending notification \(title): \(message)")
            try await notificationSender.sendNotification(title: title, message: message)
        } catch {
            log.critical("Failed to send notification: \(error)")
            assertionFailure()
        }
    }

    public func getWindowStates() async -> [WindowOpenState] {
        await windowManager.getWindowStates()
    }

    public func getActionLog(limit: Int?) async -> [ActionLogItem] {
        await actionLogManager.getActions(limit: limit)
    }

    public func clearActionLog() async {
        await actionLogManager.clear()
    }

    private func popAllFailedActions() -> [HomeManagableAction] {
        let actions = Array(failedActions.values)
        failedActions.removeAll()
        return actions
    }
}

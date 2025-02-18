//
//  HomeManager.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
import HAModels
import Logging

@HomeManagerActor
public final class HomeManager: HomeManagable {
    private let log = Logger(label: "HomeManager")
    private let getAdapter: () async -> any EntityAdapterable
    private let location: Location
    private var storageRepo: StorageRepository
    private let entityCache = Cache<EntityId, EntityStorageItem>(entryLifetime: .hours(2))
    private var failedActions: [EntityId: HomeManagableAction] = [:]

    public init(getAdapter: @escaping () async -> any EntityAdapterable, storageRepo: StorageRepository, location: Location) {
        self.getAdapter = getAdapter
        self.storageRepo = storageRepo
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
        return try await getAdapter().getAllEntitiesLive()
    }

    public func findEntity(_ entityId: EntityId) async throws {
        guard await entityCache.value(forKey: entityId) == nil else {
            // found item in cache
            return
        }
        return try await getAdapter().findEntity(entityId)
    }

    public func perform(_ action: HomeManagableAction) async {
        // add errors to failed action in this first run from external source
        await perform(action, addToFaliedActions: true)
    }

    private func perform(_ action: HomeManagableAction, addToFaliedActions: Bool) async {
        do {
            try await getAdapter().perform(action)
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
            try await getAdapter().trigger(scene: sceneName)
        } catch {
            log.critical("Failed to trigger scene [\(sceneName)]\n\(error)")
        }
    }

    public func addEntityHistory(_ item: EntityStorageItem) async {
        log.debug("Adding entity item to storage \(item.entityId)")
        await entityCache.insert(item, forKey: item.entityId)

        // persist item in the background, e.g. don't block automation execution
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
                assertionFailure()
            }
        }
    }

    public func maintenance() async throws {
        // delete storage entries older than 2 days
        let date = Date().addingTimeInterval(-1 * 2 * 24 * 60 * 60)
        try await storageRepo.deleteEntries(olderThan: date)
    }

    public func getLocation() -> Location {
        return location
    }

    private func popAllFailedActions() -> [HomeManagableAction] {
        let actions = Array(failedActions.values)
        failedActions.removeAll()
        return actions
    }
}

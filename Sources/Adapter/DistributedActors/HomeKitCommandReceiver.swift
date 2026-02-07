//
//  HomeKitCommandReceiver.swift
//  Shared
//
//  Created by Julian Kahnert on 31.01.25.
//

import Distributed
import DistributedCluster
import HAModels
import Logging
import Shared

public extension DistributedReception.Key {
    static var homeKitCommandReceiver: DistributedReception.Key<HomeKitCommandReceiver> {
        "homeKitCommandReceiver"
    }
}

/// Receiver of HomeKit commands
///
/// This should be instantiated on the HomeKitAdapter.
// public distributed actor HomeKitCommandReceiver: EntityAdapterable {  // this crashes the 6.0.3 swift compiler on linux so we moved it to an extension
public distributed actor HomeKitCommandReceiver {
    public typealias ActorSystem = ClusterSystem
    private let log = Logger(label: "HomeKitCommandReceiver")
    private let adapter: any HomeKitAdapterable

    public init(actorSystem: ActorSystem, adapter: any HomeKitAdapterable) {
        self.actorSystem = actorSystem
        self.adapter = adapter
    }

    public distributed func getAllEntitiesLive() async -> [EntityStorageItem] {
        log.info("getAllEntitiesLive() — received remote call")
        let start = ContinuousClock.now
        let entities = await adapter.getAllEntitiesLive()
        let duration = start.duration(to: .now)
        log.info("getAllEntitiesLive() — returning \(entities.count) entities in \(duration)")
        return entities
    }

    public distributed func findEntity(_ entity: EntityId) async throws {
        try await adapter.findEntity(entity)
    }

    public distributed func perform(_ action: HomeManagableAction) async throws {
        do {
            try await adapter.perform(action)
        } catch {
            log.critical("perform(_:) — failed action '\(action)': \(error)")
            throw error
        }
    }

    public distributed func trigger(scene sceneName: String) async throws {
        log.info("trigger(scene:) — received remote call for '\(sceneName)'")
        let start = ContinuousClock.now
        do {
            try await adapter.trigger(scene: sceneName)
            let duration = start.duration(to: .now)
            log.info("trigger(scene:) — completed '\(sceneName)' in \(duration)")
        } catch {
            let duration = start.duration(to: .now)
            log.critical("trigger(scene:) — failed '\(sceneName)' after \(duration): \(error)")
            throw error
        }
    }
}

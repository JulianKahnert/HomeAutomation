//
//  HomeKitCommandReceiver.swift
//  Shared
//
//  Created by Julian Kahnert on 31.01.25.
//

import Distributed
import DistributedCluster
import HAModels

extension NodeIdentity {
    public static let homeKitAdapter = NodeIdentity(id: "homeKitAdapter")
}

public extension DistributedReception.Key {
    static var homeKitCommandReceiver: DistributedReception.Key<HomeKitCommandReceiver> {
        "homeKitCommandReceiver"
    }
}

/// Receiver of HomeKit commands
///
/// This should be instantiated on the HomeKitAdapter.
public distributed actor HomeKitCommandReceiver: EntityAdapterable {
    public typealias ActorSystem = ClusterSystem
    private let adapter: any HomeKitAdapterable

    public init(actorSystem: ActorSystem, adapter: any HomeKitAdapterable) {
        self.actorSystem = actorSystem
        self.adapter = adapter
    }
    public distributed func getAllEntitiesLive() async -> [EntityStorageItem] {
        await adapter.getAllEntitiesLive()
    }

    public distributed func findEntity(_ entity: EntityId) async throws {
        try await adapter.findEntity(entity)
    }

    public distributed func perform(_ action: HomeManagableAction) async throws {
        try await adapter.perform(action)
    }

    public distributed func trigger(scene sceneName: String) async throws {
        try await adapter.trigger(scene: sceneName)
    }
}

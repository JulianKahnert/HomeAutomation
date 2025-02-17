//
//  EntityAdapterable.swift
//  
//
//  Created by Julian Kahnert on 03.07.24.
//

import Distributed

public protocol EntityAdapterable: DistributedActor {
    distributed func getAllEntitiesLive() async -> [EntityStorageItem]
    distributed func findEntity(_ entity: EntityId) async throws

    distributed func perform(_ action: HomeManagableAction) async throws
    distributed func trigger(scene sceneName: String) async throws
}

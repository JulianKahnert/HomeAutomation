//
//  UpsertScene.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation
import HAModels

public struct UpsertScene: Automatable {
    public enum Mode: Codable, Sendable {
        case allOn, allOff, goodNight
    }

    public var isActive = true
    public let name: String
    public let time: Time
    public var triggerEntityIds = Set<EntityId>()
    
    public let sceneName: String
    public let mode: Mode
    public let skippedServiceNames: Set<String>

    public init(_ name: String, at time: Time, sceneName: String, mode: Mode, skippedServiceNames: Set<String>) {
        self.name = name
        self.time = time
        self.sceneName = sceneName
        self.mode = mode
        self.skippedServiceNames = skippedServiceNames
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        return time.isEqual(event)
    }

    public func execute(using hm: HomeManagable) async throws {
        log.debug("Update all scenes")
        var entities = try await hm.getAllEntitiesLive()
        entities = entities.filter { !skippedServiceNames.contains($0.entityId.name) }

        switch mode {
        case .goodNight:
            for entity in entities {
                if entity.isDeviceOn != nil {
                    await hm.perform(.addEntityToScene(entity.entityId, sceneName: sceneName, targetValue: .off))
                } else if entity.isDoorLocked != nil {
                    await hm.perform(.addEntityToScene(entity.entityId, sceneName: sceneName, targetValue: .lockDoor))
//                } else if entity.isHeaterActive != nil {
//                    // turn on all heaters after they might be turned of for the fire place
//                    await hm.perform(.addEntityToScene(entity.entityId, sceneName: Self.sceneNameGoodNight, targetValue: .on))
                }
            }
            
        case .allOn:
            for entity in entities {
                if entity.isDeviceOn != nil {
                    await hm.perform(.addEntityToScene(entity.entityId, sceneName: sceneName, targetValue: .on))
                }
            }

        case .allOff:
            for entity in entities {
                if entity.isDeviceOn != nil {
                    await hm.perform(.addEntityToScene(entity.entityId, sceneName: sceneName, targetValue: .off))
                }
            }
        }
    }
}

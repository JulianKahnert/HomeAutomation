//
//  UpdateScenes.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation
import HAModels
#if canImport(HomeKit)
import HomeKit.HMCharacteristic
#endif

public struct UpdateScenes: Automatable {
    static let allScenesSkippedServiceNames = Set(["Wärmepumpe geringer Strompreis Modus"])
    static let sceneGoodNightSkippedServiceNames = Set(["Fußball"])
    static let sceneNameGoodNight = "Gute Nacht"
    static let sceneNameAllOn = "Alles An"
    static let sceneNameAllOff = "Alles Aus"

    public var isActive = true
    public let name: String
    public let time: Time
    public var triggerEntityIds = Set<EntityId>()

    public init(_ name: String, at time: Time) {
        self.name = name
        self.time = time
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        return time.isEqual(event)
    }

    public func execute(using hm: HomeManagable) async throws {
        log.debug("Update all scenes")
        var entities = try await hm.getAllEntitiesLive()
        entities = entities.filter { !UpdateScenes.allScenesSkippedServiceNames.contains($0.entityId.name) }

        // create/update "Gute Nacht" scene
        for entity in entities {
            guard !Self.sceneGoodNightSkippedServiceNames.contains(entity.entityId.name) else { continue }

            #if canImport(HomeKit)
            if entity.isDeviceOn != nil {
                await hm.perform(.addEntityToScene(entity.entityId, sceneName: Self.sceneNameGoodNight, targetValue: .off))
            } else if entity.isDoorLocked != nil {
                await hm.perform(.addEntityToScene(entity.entityId, sceneName: Self.sceneNameGoodNight, targetValue: .lockDoor))
//            } else if entity.isHeaterActive != nil {
//                // turn on all heaters after they might be turned of for the fire place
//                await hm.perform(.addEntityToScene(entity.entityId, sceneName: Self.sceneNameGoodNight, targetValue: .on))
            }
            #else
            log.critical("Running this automation in without HomeKit is not possible")
            assertionFailure("Running this automation in without HomeKit is not possible")
            #endif
        }

        try await Task.sleep(for: .seconds(2))

        // create/update "Alles An" scene
        for entity in entities {
            if entity.isDeviceOn != nil {
                await hm.perform(.addEntityToScene(entity.entityId, sceneName: Self.sceneNameAllOn, targetValue: .on))
            }
        }

        try await Task.sleep(for: .seconds(2))

        // create/update "Alles Aus" scene
        for entity in entities {
            if entity.isDeviceOn != nil {
                await hm.perform(.addEntityToScene(entity.entityId, sceneName: Self.sceneNameAllOff, targetValue: .off))
            }
        }
    }
}

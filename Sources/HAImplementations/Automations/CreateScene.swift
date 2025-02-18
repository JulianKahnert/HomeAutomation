//
//  CreateScene.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation
import HAModels

public struct CreateScene: Automatable {
    public var isActive = true
    public let name: String
    public let time: Time
    public let sceneName: String
    public let turnOn: Bool
    public let entities: [SwitchDevice]
    public var triggerEntityIds: Set<EntityId> {
        []
    }

    public init(_ name: String, at time: Time, sceneName: String, turnOn: Bool = true, entities: [SwitchDevice]) {
        self.name = name
        self.time = time
        self.sceneName = sceneName
        self.turnOn = turnOn
        self.entities = entities
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        return time.isEqual(event)
    }

    public func execute(using hm: HomeManagable) async throws {
        log.debug("Update the scene \(sceneName)")

        for entity in entities {
            await hm.perform(.addEntityToScene(entity.switchId, sceneName: sceneName, targetValue: .on))
        }
    }
}

//
//  TriggerScene.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation
import HAModels

public struct TriggerScene: Automatable {
    public var isActive = true
    public let name: String
    public let time: Time
    public let sceneName: String
    public var triggerEntityIds: Set<EntityId> {
        []
    }

    public init(_ name: String, at time: Time, sceneName: String) {
        self.name = name
        self.time = time
        self.sceneName = sceneName
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        return time.isEqual(event)
    }

    public func execute(using hm: HomeManagable) async throws {
        log.debug("Trigger scene: '\(sceneName)'")

        await hm.trigger(scene: sceneName)
    }
}

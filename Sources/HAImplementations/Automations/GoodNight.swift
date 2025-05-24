//
//  TurnOff.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation
import HAModels

public struct GoodNight: Automatable {
    public var isActive = true
    public let name: String
    public let time: Time
    public var triggerEntityIds: Set<EntityId> {
        []
    }

    public init(_ name: String, at time: Time) {
        self.name = name
        self.time = time
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        return time.isEqual(event)
    }

    public func execute(using hm: HomeManagable) async throws {
        log.debug("Trigger good night scene to turn off devices + close locks")

        await hm.trigger(scene: UpdateScenes.sceneNameGoodNight)
    }
}

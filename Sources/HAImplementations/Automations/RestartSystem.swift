//
//  RestartSystem.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation
import HAModels

public struct RestartSystem: Automatable {
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
        log.debug("Shutting system down - it should be restarted by LaunchD")
        exit(1)
    }
}

//
//  TurnOnForDuration.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation
import HAModels

public struct TurnOnForDuration: Automatable {
    public let name: String
    public let time: Time
    public let duration: Duration
    public let switches: [SwitchDevice]
    public var triggerEntityIds = Set<EntityId>()

    public init(_ name: String, at time: Time, for duration: Duration, switches: [SwitchDevice]) {
        self.name = name
        self.time = time
        self.duration = duration
        self.switches = switches
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        return time.isEqual(event)
    }

    public func execute(using hm: HomeManagable) async throws {
        log.debug("Turning on devices")
        for device in switches {
            await device.turnOn(with: hm)
        }

        try await Task.sleep(for: duration)

        for device in switches {
            await device.turnOff(with: hm)
        }
    }
}

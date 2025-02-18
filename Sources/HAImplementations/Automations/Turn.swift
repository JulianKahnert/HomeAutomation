//
//  TurnOff.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 20.07.24.
//

import Foundation
import HAModels

public struct Turn: Automatable {
    public enum State: String, Sendable, Codable {
        case on, off
    }
    public var isActive = true
    public let name: String
    public let state: State
    public let time: Time
    public let onlyBeforeSunrise: Bool
    public let switches: [SwitchDevice]
    public let heatSwitches: [HeatSwitch]
    public var triggerEntityIds: Set<EntityId> {
        []
    }

    public init(_ state: State, _ name: String, at time: Time, onlyBeforeSunrise: Bool = false, switches: [SwitchDevice], heatSwitches: [HeatSwitch] = []) {
        self.name = name
        self.state = state
        self.time = time
        self.onlyBeforeSunrise = onlyBeforeSunrise
        self.switches = switches
        self.heatSwitches = heatSwitches
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        if onlyBeforeSunrise {
            let isTimeEqual = time.isEqual(event)

            let location = await hm.getLocation()
            let elevation = Sun.position(latitude: location.latitude, longitude: location.longitude, date: Date())?.elevation
            guard let elevation else {
                assertionFailure("Failed to get sun elevation")
                return isTimeEqual
            }

            return isTimeEqual && elevation < 0
        } else {
            return time.isEqual(event)
        }
    }

    public func execute(using hm: HomeManagable) async throws {
        log.debug("Turning devices \(state == .on ? "on" : "off")")
        for device in switches {
            switch state {
            case .on:
                await device.turnOn(with: hm)
            case .off:
                await device.turnOff(with: hm)
            }
        }

        for heatSwitch in heatSwitches {
            switch state {
            case .on:
                await heatSwitch.turn(on: true, with: hm)
            case .off:
                await heatSwitch.turn(on: false, with: hm)
            }
        }
    }
}

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
            guard isTimeEqual else { return false }

            // Uses Sun.sunriseElevation — the same method ClockJob uses to
            // emit .sunrise events — so both always agree on the sunrise minute.
            let location = await hm.getLocation()
            guard case .time(let date) = event else { return false }
            guard let elevation = Sun.sunriseElevation(for: date, latitude: location.latitude, longitude: location.longitude) else {
                assertionFailure("Failed to get sunrise time")
                return true
            }

            return elevation == .below
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

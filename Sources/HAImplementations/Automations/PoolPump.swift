//
//  PoolPump.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 03.09.24.
//

import Foundation
import HAModels

public struct PoolPump: Automatable {
    public let name: String
    // switches that should be ACTIVATED when the energy price is low
    public let pumpSwitch: SwitchDevice
    public var triggerEntityIds = Set<EntityId>()

    public init(_ name: String, pumpSwitch: SwitchDevice) {
        self.name = name
        self.pumpSwitch = pumpSwitch
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        guard case let HomeEvent.time(date: date) = event else {
            return false
        }

        return Calendar.current.component(.minute, from: date) == 0
    }

    public func execute(using hm: HomeManagable) async throws {
        log.debug("Get price infos")
#warning("TODO: add again")
//        let tibber = TibberService.shared

        var shouldTurnOnSwitches = false
//        if await tibber.getPriceIfCurrentlyLowestPriceHour() != nil {
//            shouldTurnOnSwitches = true
//        } else if await tibber.getPriceIfCurrentlySecondLowestPriceHour() != nil {
//            shouldTurnOnSwitches = true
//        }

        #warning("TODO: fix problem - manually turned on pool will be turned off every hour")
        if shouldTurnOnSwitches {
            await pumpSwitch.turnOn(with: hm)
        } else {
            await pumpSwitch.turnOff(with: hm)
        }
    }
}

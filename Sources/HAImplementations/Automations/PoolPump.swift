//
//  PoolPump.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 03.09.24.
//

import Foundation
import HAModels

public struct PoolPump: Automatable {
    public var isActive = true
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
        guard let tibber = TibberService() else { return }

        let isCurrentlyLowestPrice = await tibber.getPriceIfCurrentlyLowestPriceHour() != nil
        let isCurrentlySecondLowestPrice = await tibber.getPriceIfCurrentlySecondLowestPriceHour() != nil
        guard isCurrentlyLowestPrice || isCurrentlySecondLowestPrice else { return }

        // turn on pool pump for 58 minutes
        await pumpSwitch.turnOn(with: hm)

        try await Task.sleep(for: .minutes(58))

        // turn it off afterwards
        await pumpSwitch.turnOff(with: hm)
    }
}

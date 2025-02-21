//
//  EveningLight.swift
//
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
import HAModels

public struct EnergyLowPrice: Automatable {
    public var isActive = true
    public let name: String
    // the devices will only be triggered, if the price is below this threshold
    private static let thresholdInEUR = 0.18
    // switches that should be ACTIVATED when the energy price is low
    public let switches: [SwitchDevice]
    public var triggerEntityIds: Set<EntityId> {
        []
    }

    public init(_ name: String, switches: [SwitchDevice]) {
        self.name = name
        self.switches = switches
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        guard case let HomeEvent.time(date: date) = event else {
            return false
        }

        return Calendar.current.component(.minute, from: date) == 0
    }

    public func execute(using hm: HomeManagable) async throws {
        log.debug("Get price infos")
        let tibber = TibberService()

        var shouldTurnOnSwitches = false
        if let lowestPrice = await tibber?.getPriceIfCurrentlyLowestPriceHour() {
            log.info("Found lowest price: \(lowestPrice)")
            shouldTurnOnSwitches = lowestPrice <= Self.thresholdInEUR
        } else if let secondLowestPrice = await tibber?.getPriceIfCurrentlySecondLowestPriceHour() {
            log.info("Found second lowest price: \(secondLowestPrice)")
            shouldTurnOnSwitches = secondLowestPrice <= Self.thresholdInEUR
        }

        for enerySwitch in switches {
            if shouldTurnOnSwitches {
                await enerySwitch.turnOn(with: hm)
                await tibber?.sendNotification(title: "Low energy price", message: "\(Date().formatted())")
            } else {
                await enerySwitch.turnOff(with: hm)
            }
        }
    }
}

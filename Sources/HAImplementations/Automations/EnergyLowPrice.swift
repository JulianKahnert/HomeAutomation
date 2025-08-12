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

    /// switches that should be ACTIVATED when the energy price is low
    public let switches: [SwitchDevice]

    /// The time the switches should run per day
    public let dailyActivationDuration: Duration

    /// the devices will only be triggered, if the price is lower or equal to this threshold
    public let thresholdInEUR: Double?
    public var triggerEntityIds: Set<EntityId> {
        []
    }

    public init(_ name: String, switches: [SwitchDevice], dailyActivationDuration: Duration = .hours(2), thresholdInEUR: Double?) {
        self.name = name
        self.switches = switches
        self.dailyActivationDuration = dailyActivationDuration
        self.thresholdInEUR = thresholdInEUR
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

        var prices = try await tibber.getCheapestPricesToday(for: dailyActivationDuration)

        // if there is a threshold set, we must filter the prices first
        if let thresholdInEUR {
            prices = prices.filter { $0.price <= thresholdInEUR }
        }

        let shouldTurnOnSwitches: Bool
        if let price = prices.first(where: { $0.time.contains(Date()) }) {
            log.info("Starting switches as current price is \(price.price)€/kWh")
            shouldTurnOnSwitches = true
        } else {
            shouldTurnOnSwitches = false
        }

        for enerySwitch in switches {
            if shouldTurnOnSwitches {
                await enerySwitch.turnOn(with: hm)
//                await tibber?.sendNotification(title: "Low energy price", message: "\(Date().formatted())")
            } else {
                await enerySwitch.turnOff(with: hm)
            }
        }
    }
}

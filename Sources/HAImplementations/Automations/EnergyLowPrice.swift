//
//  EveningLight.swift
//
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
import HAModels
import Shared

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

        return Calendar.current.component(.minute, from: date) == 3
    }

    public func execute(using hm: HomeManagable) async throws {
        log.debug("Get price infos")
        // The current price is state (reported by the server's EnergyPriceJob); Tibber only ranks today's slots.
        guard let current = await hm.states(of: CharacteristicsType.energyPrice.valueKind)
                .first(where: { $0.entityId == .electricityPrice })?.energyPriceInEURPerKWh else {
            log.warning("No electricity price known, switching off")
            await setSwitches(on: false, using: hm)
            return
        }
        guard let tibber = TibberService() else { return }

        var prices = try await tibber.getCheapestPricesToday(for: dailyActivationDuration)

        // if there is a threshold set, we must filter the prices first
        if let thresholdInEUR {
            prices = prices.filter { $0.price <= thresholdInEUR }
        }

        // The current slot is one of the cheapest when its price does not exceed the dearest of them.
        let shouldTurnOnSwitches = Self.isCheap(current, among: prices.map(\.price))
        if shouldTurnOnSwitches {
            log.info("Starting switches as current price is \(current)€/kWh")
        }
        await setSwitches(on: shouldTurnOnSwitches, using: hm)
    }

    /// Whether `price` is within the cheapest slots, given their prices (already filtered by the threshold).
    static func isCheap(_ price: Double, among cheapest: [Double]) -> Bool {
        guard let dearest = cheapest.max() else { return false }
        return price <= dearest
    }

    private func setSwitches(on: Bool, using hm: HomeManagable) async {
        for enerySwitch in switches {
            if on {
                await enerySwitch.turnOn(with: hm)
            } else {
                await enerySwitch.turnOff(with: hm)
            }
        }
    }
}

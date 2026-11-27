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

    /// The price job reports every 15 minutes; a price older than two reports is no longer current.
    static let maximumPriceAge: TimeInterval = 30 * 60
    private static let missingPrice = Disturbances<String>()

    public func execute(using hm: HomeManagable) async throws {
        log.debug("Get price infos")
        guard let current = await currentPrice(using: hm, now: Date()) else { return }
        guard let tibber = TibberService() else { return }

        let slots = try await tibber.getCheapestPricesToday(for: dailyActivationDuration)
        await apply(cheapestSlots: slots, currentPrice: current, now: Date(), using: hm)
    }

    /// The current price (state reported by the server's EnergyPriceJob), `nil` while none is known or the last report is
    /// too old: after a restart before the job ran, or while the source is down. Logs once per disturbance.
    func currentPrice(using hm: HomeManagable, now: Date) async -> Double? {
        let price = await hm.states(of: CharacteristicsType.energyPrice.valueKind)
            .first { $0.entityId == .electricityPrice }?.energyPriceInEURPerKWh
        if let price, let reported = await hm.lastReport(of: .electricityPrice), now.timeIntervalSince(reported) <= Self.maximumPriceAge {
            if await Self.missingPrice.recovered(name) {
                log.info("The electricity price is known again", metadata: ["automation": "\(name)"])
            }
            return price
        }
        if await Self.missingPrice.began(name) {
            log.warning("No current electricity price known, leaving the switches as they are", metadata: ["automation": "\(name)"])
        }
        return nil
    }

    /// Switches on when the current time slot is one of the cheapest slots (those under the threshold, if one is set),
    /// off otherwise. Tibber's ranking decides, so a tie in price never extends beyond `dailyActivationDuration`.
    func apply(cheapestSlots: [TibberService.TodayPrice], currentPrice: Double, now: Date, using hm: HomeManagable) async {
        var slots = cheapestSlots
        if let thresholdInEUR {
            slots = slots.filter { $0.price <= thresholdInEUR }
        }
        let shouldTurnOnSwitches = slots.contains { $0.time.contains(now) }
        if shouldTurnOnSwitches {
            log.info("Starting switches in a cheapest slot", metadata: ["priceInEURPerKWh": "\(currentPrice)"])
        }
        await setSwitches(on: shouldTurnOnSwitches, using: hm)
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

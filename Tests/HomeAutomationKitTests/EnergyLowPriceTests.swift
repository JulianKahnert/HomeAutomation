//
//  EnergyLowPriceTests.swift
//  HomeAutomation
//

import Foundation
@testable import HAImplementations
import HAModels
import Testing

@HomeManagerActor
struct EnergyLowPriceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let lamp = EntityId(placeId: "p", name: "lamp", characteristicsName: nil, characteristic: .switcher)
    private let homeManager = MockHomeAdapter()
    private var automation: EnergyLowPrice {
        EnergyLowPrice("Low price", switches: [SwitchDevice(switchId: lamp, brightnessId: nil, colorTemperatureId: nil, rgbId: nil)], thresholdInEUR: nil)
    }

    private func slot(_ startOffset: TimeInterval, price: Double) -> TibberService.TodayPrice {
        .init(time: now.addingTimeInterval(startOffset)...now.addingTimeInterval(startOffset + 3_599), price: price)
    }

    @Test("only the current slot of the cheapest slots switches on, a slot of the same price outside them does not")
    func onlyCheapestSlotsSwitchOn() async {
        let cheapest = [slot(-7_200, price: 0.10), slot(-3_600, price: 0.10)]

        // 0.10 € is the current price but this slot is not among the cheapest ones Tibber ranked
        await automation.apply(cheapestSlots: cheapest, currentPrice: 0.10, now: now, using: homeManager)
        #expect(homeManager.performedActions.map(\.action) == [.turnOff(lamp)])

        await automation.apply(cheapestSlots: cheapest + [slot(-1_800, price: 0.10)], currentPrice: 0.10, now: now, using: homeManager)
        #expect(homeManager.performedActions.last?.action == .turnOn(lamp))
    }

    @Test("a threshold removes the slots above it")
    func thresholdFiltersSlots() async {
        let capped = EnergyLowPrice("Low price", switches: [SwitchDevice(switchId: lamp, brightnessId: nil, colorTemperatureId: nil, rgbId: nil)], thresholdInEUR: 0.05)

        await capped.apply(cheapestSlots: [slot(-1_800, price: 0.10)], currentPrice: 0.10, now: now, using: homeManager)

        #expect(homeManager.performedActions.map(\.action) == [.turnOff(lamp)])
    }

    @Test("without a known current price the switches stay as they are")
    func noPriceKnownDoesNothing() async {
        #expect(await automation.currentPrice(using: homeManager, now: now) == nil)
        #expect(homeManager.performedActions.isEmpty)
    }

    @Test("a price known as state but never reported in this process is not current")
    func priceFromBeforeTheRestartIsNotCurrent() async {
        await homeManager.report(.electricityPrice, value: .number(0.2), origin: .job("EnergyPriceJob"))
        homeManager.lastReports[.electricityPrice] = nil

        #expect(await automation.currentPrice(using: homeManager, now: now) == nil)
    }

    @Test("a price report older than the price job's cadence allows is not current, a fresh one is")
    func stalePriceIsNotCurrent() async {
        await homeManager.report(.electricityPrice, value: .number(0.2), origin: .job("EnergyPriceJob"))

        homeManager.lastReports[.electricityPrice] = now.addingTimeInterval(-EnergyLowPrice.maximumPriceAge - 1)
        #expect(await automation.currentPrice(using: homeManager, now: now) == nil)

        homeManager.lastReports[.electricityPrice] = now.addingTimeInterval(-60)
        #expect(await automation.currentPrice(using: homeManager, now: now) == 0.2)
    }
}

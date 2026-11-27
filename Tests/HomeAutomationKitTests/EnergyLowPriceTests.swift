//
//  EnergyLowPriceTests.swift
//  HomeAutomation
//

@testable import HAImplementations
import Testing

struct EnergyLowPriceTests {
    @Test func currentPriceIsCheapWithinTheCheapestSlots() {
        #expect(EnergyLowPrice.isCheap(0.20, among: [0.15, 0.20]))
        #expect(EnergyLowPrice.isCheap(0.10, among: [0.15, 0.20]))
        #expect(!EnergyLowPrice.isCheap(0.21, among: [0.15, 0.20]))
        #expect(!EnergyLowPrice.isCheap(0.10, among: []))
    }
}

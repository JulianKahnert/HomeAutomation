//
//  EnergyPriceJobTests.swift
//  HomeAutomation
//

import Foundation
@testable import HAModels
@testable import Server
import Testing

struct EnergyPriceJobTests {
    @Test func reportsTheCurrentPriceAsServerOwnedEntity() async throws {
        let reports = Reports()
        let job = EnergyPriceJob(currentPrice: { _ in 0.27 }, report: { await reports.add($0, $1, $2) })

        try await job.run(plannedAt: Date(timeIntervalSince1970: 100))

        let all = await reports.all
        #expect(all.count == 1)
        #expect(all[0].0 == .serverOwned(name: "electricityPrice", characteristic: .energyPrice))
        #expect(all[0].1 == .number(0.27))
        #expect(all[0].2 == .job("EnergyPriceJob"))
    }

    @Test func failingSourceThrowsAndReportsNothing() async {
        let reports = Reports()
        let job = EnergyPriceJob(currentPrice: { _ in throw URLError(.notConnectedToInternet) }, report: { await reports.add($0, $1, $2) })

        await #expect(throws: (any Error).self) { try await job.run(plannedAt: Date()) }
        #expect(await reports.all.isEmpty)
    }

    @Test func noPriceForNowIsAFailure() async {
        let job = EnergyPriceJob(currentPrice: { _ in nil }, report: { _, _, _ in true })
        await #expect(throws: (any Error).self) { try await job.run(plannedAt: Date()) }
    }
}

struct DisturbancesTests {
    @Test func aFailureIsNewOnlyOncePerDisturbance() async {
        let disturbances = Disturbances<String>()
        #expect(await disturbances.began("job"))
        #expect(await !disturbances.began("job"))
        #expect(await disturbances.recovered("job"))
        #expect(await !disturbances.recovered("job"))
        #expect(await disturbances.began("job"))
    }
}

//
//  EnergyPriceJob.swift
//  HomeAutomationServer
//

import Foundation
import HAModels
import Logging
import Shared

/// Reports the current electricity price as the server-owned entity ``entityId`` with the origin of this job.
/// A source that fails or knows no price for now fails the run, so `/health` shows the job's last success.
struct EnergyPriceJob: ScheduledJob, Log {
    struct NoPriceError: Error {}

    static let entityId = EntityId.electricityPrice

    let name = "EnergyPriceJob"
    let cadence: Duration = .minutes(15)
    let runsAtStart = true

    /// The price in EUR per kWh that is valid at the given date, `nil` without one.
    let currentPrice: @Sendable (Date) async throws -> Double?
    /// Reports a value of a server-owned entity (`HomeManagable.report`).
    let report: @Sendable (EntityId, Value, Origin) async -> Bool

    func run(plannedAt: Date) async throws {
        guard let price = try await currentPrice(plannedAt) else { throw NoPriceError() }
        _ = await report(Self.entityId, .number(price), .job(name))
    }
}

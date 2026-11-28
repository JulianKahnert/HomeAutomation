//
//  ValveJob.swift
//  HomeAutomationServer
//

import Foundation
import HAModels
import Logging
import Shared

/// Asks the adapter every five minutes for valve position and offset of every thermostat, one thermostat per
/// call, and feeds the values into the event stream with origin `ValveJob`. A thermostat that does not answer
/// delays only its own read and is logged once per disturbance. The run fails when no thermostat could be read, so
/// `/health` keeps the last success.
struct ValveJob: ScheduledJob, Log {
    struct NoThermostatReadableError: Error {}

    let name = "ValveJob"
    let cadence: Duration = .minutes(5)
    let runsAtStart = true

    let listThermostats: @Sendable () async throws -> [Thermostat]
    let readThermostat: @Sendable (Thermostat) async throws -> [EntityStorageItem]
    /// Hands one item into the event stream.
    let feed: @Sendable (EntityStorageItem) -> Void
    private let disturbances = Disturbances<Thermostat>()

    init(listThermostats: @escaping @Sendable () async throws -> [Thermostat],
         readThermostat: @escaping @Sendable (Thermostat) async throws -> [EntityStorageItem],
         feed: @escaping @Sendable (EntityStorageItem) -> Void) {
        self.listThermostats = listThermostats
        self.readThermostat = readThermostat
        self.feed = feed
    }

    func run(plannedAt: Date) async throws {
        let thermostats = try await listThermostats()
        let readable = await withTaskGroup(of: Bool.self) { group in
            for thermostat in thermostats {
                group.addTask { await poll(thermostat) }
            }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        if !thermostats.isEmpty, readable == 0 {
            throw NoThermostatReadableError()
        }
    }

    /// - Returns: Whether the thermostat was read.
    private func poll(_ thermostat: Thermostat) async -> Bool {
        do {
            let items = try await readThermostat(thermostat)
            if await disturbances.recovered(thermostat) {
                log.info("Thermostat readable again", metadata: ["thermostat": "\(thermostat)"])
            }
            for var item in items {
                item.origin = .job(name)
                feed(item)
            }
            return true
        } catch {
            if await disturbances.began(thermostat) {
                log.warning("Failed to read thermostat", metadata: ["thermostat": "\(thermostat)", "error": "\(error)"])
            } else {
                log.debug("Thermostat still not readable", metadata: ["thermostat": "\(thermostat)", "error": "\(error)"])
            }
            return false
        }
    }
}

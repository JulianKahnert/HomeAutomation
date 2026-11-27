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
/// delays only its own read and is logged once per disturbance.
struct ValveJob: ScheduledJob, Log {
    let name = "ValveJob"
    let cadence: Duration = .minutes(5)
    let runsAtStart = true

    let listThermostats: @Sendable () async throws -> [Thermostat]
    let readThermostat: @Sendable (Thermostat) async throws -> [EntityStorageItem]
    /// Hands one item into the event stream.
    let feed: @Sendable (EntityStorageItem) -> Void
    private let disturbances = Disturbances()

    init(listThermostats: @escaping @Sendable () async throws -> [Thermostat],
         readThermostat: @escaping @Sendable (Thermostat) async throws -> [EntityStorageItem],
         feed: @escaping @Sendable (EntityStorageItem) -> Void) {
        self.listThermostats = listThermostats
        self.readThermostat = readThermostat
        self.feed = feed
    }

    func run(plannedAt: Date) async throws {
        let thermostats = try await listThermostats()
        await withTaskGroup(of: Void.self) { group in
            for thermostat in thermostats {
                group.addTask { await poll(thermostat) }
            }
        }
    }

    private func poll(_ thermostat: Thermostat) async {
        do {
            let items = try await readThermostat(thermostat)
            if await disturbances.recovered(thermostat) {
                log.info("Thermostat readable again", metadata: ["thermostat": "\(thermostat)"])
            }
            for var item in items {
                item.origin = .job(name)
                feed(item)
            }
        } catch {
            if await disturbances.began(thermostat) {
                log.warning("Failed to read thermostat", metadata: ["thermostat": "\(thermostat)", "error": "\(error)"])
            } else {
                log.debug("Thermostat still not readable", metadata: ["thermostat": "\(thermostat)", "error": "\(error)"])
            }
        }
    }

    private actor Disturbances {
        private var failing: Set<Thermostat> = []
        func began(_ thermostat: Thermostat) -> Bool { failing.insert(thermostat).inserted }
        func recovered(_ thermostat: Thermostat) -> Bool { failing.remove(thermostat) != nil }
    }
}

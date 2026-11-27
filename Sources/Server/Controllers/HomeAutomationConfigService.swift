//
//  HomeAutomationConfigService.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 14.02.25.
//

import Fluent
import Foundation
import HAApplicationLayer
import HAImplementations
import HAModels
import Logging
import Shared

/// Holds the location and stores the configuration; the automations themselves live in the `AutomationService`.
actor HomeAutomationConfigService: Log, AutomationRepository {
    private static let defaultLocation = Location(latitude: 53.14194, longitude: 8.21292)
    // TODO: remove the one-time import one release after the config moved into the database
    private static let legacyFileURL = URL(fileURLWithPath: "/tmp/HomeAutomation-config.json")

    private(set) var location: Location
    private let persist: @Sendable (Data) async throws -> Void

    init(location: Location, persist: @escaping @Sendable (Data) async throws -> Void) {
        self.location = location
        self.persist = persist
    }

    /// Takes the location of a deployed config; it is stored with the next `save`.
    func set(location: Location) {
        self.location = location
    }

    func save(_ automations: [any Automatable]) async throws {
        let configDto = ConfigDTO(location: location, automations: automations.map(AnyAutomation.create(from:)))
        try await persist(JSONEncoder().encode(configDto))
    }

    /// - Parameter database: Resolved per query, so saves are not tied to one event loop's pool.
    static func load(from database: @escaping @Sendable () -> any Database) async -> (service: HomeAutomationConfigService, automations: [any Automatable]) {
        let persist: @Sendable (Data) async throws -> Void = { try await ConfigItem.save(json: $0, on: database()) }
        do {
            var data = try await ConfigItem.loadJSON(on: database())
            if data == nil, FileManager.default.fileExists(atPath: legacyFileURL.path) {
                log.notice("Importing legacy config file into the database")
                let legacyData = try Data(contentsOf: legacyFileURL)
                try await persist(legacyData)
                data = legacyData
            }
            guard let data else {
                log.info("No config stored yet - falling back to default config")
                return (Self(location: defaultLocation, persist: persist), [])
            }
            let config = try JSONDecoder().decode(ConfigDTO.self, from: data)
            return (Self(location: config.location, persist: persist), config.automations.map(\.automation))
        } catch {
            log.error("Failed to load config - falling back to default config: \(error)")
            return (Self(location: defaultLocation, persist: persist), [])
        }
    }
}

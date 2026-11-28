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

    /// Saves are serialized by the `AutomationService`, which hands them over in the order of the changes.
    func save(_ automations: [any Automatable], location newLocation: Location?) async throws {
        if let newLocation { location = newLocation }
        let configDto = ConfigDTO(location: location, automations: automations.map(AnyAutomation.create(from:)))
        try await persist(try JSONEncoder().encode(configDto))
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

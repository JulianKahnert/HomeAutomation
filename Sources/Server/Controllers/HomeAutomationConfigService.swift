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
    static let defaultLocation = Location(latitude: 53.14194, longitude: 8.21292)
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
    /// - Returns: `isReadable` is `false` when the stored config could not be read, so nothing may overwrite it.
    static func load(from database: @escaping @Sendable () -> any Database) async -> (service: HomeAutomationConfigService, automations: [any Automatable], isReadable: Bool) {
        let persist: @Sendable (Data) async throws -> Void = { try await ConfigItem.save(json: $0, on: database()) }
        do {
            if try await ConfigItem.loadJSON(on: database()) == nil, FileManager.default.fileExists(atPath: legacyFileURL.path) {
                log.notice("Importing legacy config file into the database")
                try await persist(try Data(contentsOf: legacyFileURL))
            }
            // The one place that decodes the stored config and falls back to the default location.
            let config = try await ConfigDbRepository(database: database).load()
            return (Self(location: config.location, persist: persist), config.automations.map(\.automation), true)
        } catch {
            log.error("Failed to load config - falling back to default config: \(error)")
            return (Self(location: defaultLocation, persist: persist), [], false)
        }
    }
}

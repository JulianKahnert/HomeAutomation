//
//  HomeAutomationConfigService.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 14.02.25.
//

import Fluent
import Foundation
import HAImplementations
import HAModels
import Logging
import Shared

actor HomeAutomationConfigService: Log {
    private static let defaultLocation = Location(latitude: 53.14194, longitude: 8.21292)
    // TODO: remove the one-time import one release after the config moved into the database
    private static let legacyFileURL = URL(fileURLWithPath: "/tmp/HomeAutomation-config.json")

    private(set) var location: Location
    private(set) var automations: [any Automatable]
    private let persist: @Sendable (Data) async throws -> Void

    init(location: Location, automations: [any Automatable], persist: @escaping @Sendable (Data) async throws -> Void) {
        self.location = location
        self.automations = automations
        self.persist = persist
    }

    func set(location: Location, automations: [any Automatable]) async throws {
        self.location = location
        self.automations = automations

        try await save()
    }

    func setAutomationActive(with name: String, to value: Bool) async throws {
        automations = automations.map { automation in
            var automation = automation
            if automation.name == name {
                automation.isActive = value
            }
            return automation
        }
        try await save()
    }

    func save() async throws {
        let configDto = ConfigDTO(location: location, automations: automations.map(AnyAutomation.create(from:)))
        try await persist(JSONEncoder().encode(configDto))
    }

    static func load(from database: any Database) async -> Self {
        let persist: @Sendable (Data) async throws -> Void = { try await ConfigItem.save(json: $0, on: database) }
        do {
            var data = try await ConfigItem.loadJSON(on: database)
            if data == nil, FileManager.default.fileExists(atPath: legacyFileURL.path) {
                log.notice("Importing legacy config file into the database")
                let legacyData = try Data(contentsOf: legacyFileURL)
                try await persist(legacyData)
                data = legacyData
            }
            guard let data else {
                log.info("No config stored yet - falling back to default config")
                return Self(location: defaultLocation, automations: [], persist: persist)
            }
            let config = try JSONDecoder().decode(ConfigDTO.self, from: data)
            return Self(location: config.location, automations: config.automations.map(\.automation), persist: persist)
        } catch {
            log.error("Failed to load config - falling back to default config: \(error)")
            return Self(location: defaultLocation, automations: [], persist: persist)
        }
    }
}

//
//  HomeAutomationConfigService.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 14.02.25.
//

import Foundation
import HAImplementations
import HAModels
import Logging
import Shared

actor HomeAutomationConfigService: Log {
    static let url = URL(fileURLWithPath: "/tmp/HomeAutomation-config.json")
    private(set) var location: Location
    private(set) var automations: [any Automatable]

    init(location: Location, automations: [any Automatable]) {
        self.location = location
        self.automations = automations
    }

    func set(location: Location, automations: [any Automatable]) throws {
        self.location = location
        self.automations = automations

        try save()
    }

    func setAutomationActive(with name: String, to value: Bool) {
        let automations = self.automations.map { automation in
            var automation = automation
            if automation.name == name {
                automation.isActive = value
            }
            return automation
        }
        self.automations = automations
    }

    func save() throws {
        let automations = automations.map(AnyAutomation.create(from:))
        let configDto = ConfigDTO(location: location, automations: automations)
        let data = try JSONEncoder().encode(configDto)
        try data.write(to: Self.url)
    }

    static func loadOrDefault() -> Self {
        do {
            let data = try Data(contentsOf: url)
            let config = try JSONDecoder().decode(ConfigDTO.self, from: data)
            let automations = config.automations.map(\.automation)
            return Self(location: config.location, automations: automations)
        } catch {
            log.error("Failed to parse config file - falling back to defaults: \(error)")
            log.info("Falling back to default config: \(Location(latitude: 53.14194, longitude: 8.21292)) - automations: []")
            return .init(location: Location(latitude: 53.14194, longitude: 8.21292), automations: [])
        }
    }
}

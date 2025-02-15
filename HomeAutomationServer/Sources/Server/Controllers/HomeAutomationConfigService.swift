//
//  HomeAutomationConfigService.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 14.02.25.
//

import Foundation
import HAImplementations
import HAModels

actor HomeAutomationConfigService {
    static let url = URL(fileURLWithPath: "/tmp/HomeAutomation-config.json")
    private(set) var location: Location
    private(set) var automations: [AnyAutomation] = []

    init(location: Location, automations: [AnyAutomation]) {
        self.location = location
    }

    func set(location: Location, automations: [AnyAutomation]) throws {
        self.location = location
        self.automations = automations

        try save()
    }

    func save() throws {
        let configDto = ConfigDTO(location: location, automations: automations)
        let data = try JSONEncoder().encode(configDto)
        try data.write(to: Self.url)
    }

    static func load() async throws -> Self {
        let data = try Data(contentsOf: url)
        let config = try JSONDecoder().decode(ConfigDTO.self, from: data)
        return Self(location: config.location, automations: config.automations)
    }
}

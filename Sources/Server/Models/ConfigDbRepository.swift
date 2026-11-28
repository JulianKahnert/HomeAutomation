//
//  ConfigDbRepository.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAImplementations

/// Reads the deployed configuration (location and automations with their active state) from the database.
protocol ConfigReading: Sendable {
    /// The stored configuration; the default location without automations when nothing is stored yet.
    func load() async throws -> ConfigDTO
}

struct ConfigDbRepository: ConfigReading {
    /// Resolved per query, like the other repositories.
    let database: @Sendable () -> any Database

    func load() async throws -> ConfigDTO {
        guard let data = try await ConfigItem.loadJSON(on: database()) else {
            return ConfigDTO(location: HomeAutomationConfigService.defaultLocation, automations: [])
        }
        return try JSONDecoder().decode(ConfigDTO.self, from: data)
    }
}

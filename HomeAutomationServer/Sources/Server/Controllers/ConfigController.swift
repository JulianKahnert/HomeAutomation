//
//  ConfigController.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 14.02.25.
//

import Fluent
import HAImplementations
import Vapor

struct ConfigController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let config = routes.grouped("config")

        config.get(use: self.index)
        config.post(use: self.update)
    }

    @Sendable
    func index(req: Request) async throws -> ConfigDTO {
        let location = await req.application.homeAutomationConfigService.location
        let automations = await req.application.homeAutomationConfigService.automations

        return ConfigDTO(location: location, automations: automations)
    }

    @Sendable
    func update(req: Request) async throws -> ConfigDTO {
        let configDTO = try req.content.decode(ConfigDTO.self)
        try await req.application.homeAutomationConfigService.set(location: configDTO.location, automations: configDTO.automations)

        return configDTO
    }
}

//
//  ConfigController.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 14.02.25.
//

import Fluent
import HAImplementations
import HAModels
import Vapor

struct ConfigController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        let config = routes.grouped("config")

        config.get(use: self.index)
        config.on(.POST, body: .collect(maxSize: "10mb"), use: self.update)
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

        // validate if all automations are correct, e.g. contain existing entities
        let configEntityIds = configDTO.automations
            .map(\.automation)
            .flatMap { $0.getEntityIds() }
            .reduce(into: Set<EntityId>()) { partialResult, entityId in
                partialResult.insert(entityId)
            }
        let foundEntityIds = try await req.application.homeManager.getAllEntitiesLive()

        let missingEntityIds = configEntityIds.subtracting(foundEntityIds.map(\.entityId))
        guard missingEntityIds.isEmpty else {
            throw Abort(.badRequest, reason: "Validation failed - Could not find the following entities: \(missingEntityIds)")
        }

        try await req.application.homeAutomationConfigService.set(location: configDTO.location, automations: configDTO.automations)

        return configDTO
    }
}

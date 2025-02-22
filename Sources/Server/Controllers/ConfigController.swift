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

        let automations = config.grouped("automations")
        automations.get(use: self.automationsIndex)
        automations.group(":name") { automation in
            automation.post("activate", use: self.automationsActivate)
            automation.post("deactivate", use: self.automationsDeactivate)
        }
    }

    @Sendable
    func index(req: Request) async throws -> ConfigDTO {
        let location = await req.application.homeAutomationConfigService.location
        let automations = await req.application.homeAutomationConfigService.automations.map(AnyAutomation.create(from:))

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
            throw Abort(.unprocessableEntity, reason: "Validation failed - Could not find the following entities: \(missingEntityIds)")
        }

        let previousAutomations = await req.application.homeAutomationConfigService.automations
        let automations = configDTO.automations
            .map(\.automation)
            .map { automation in
                var automation = automation
                guard let foundAutomation = previousAutomations.first(where: { $0.name == automation.name }) else { return automation }
                automation.isActive = foundAutomation.isActive
                return automation
            }

        try await req.application.homeAutomationConfigService.set(location: configDTO.location, automations: automations)

        return configDTO
    }

    // MARK: - /config/automations

    @Sendable
    func automationsIndex(req: Request) async throws -> [AutomationDTO] {
        await req.application.homeAutomationConfigService.automations
            .map { tmp in
                AutomationDTO(name: tmp.name, isActive: tmp.isActive, isRunning: false)
            }
    }

    @Sendable
    func automationsActivate(req: Request) async throws -> HTTPStatus {
        guard let name = req.parameters.get("name"),
              !name.isEmpty else {
            throw Abort(.notFound, reason: "Automation name not provided")
        }

        await req.application.homeAutomationConfigService.setAutomationActive(with: name, to: true)
        return .ok
    }

    @Sendable
    func automationsDeactivate(req: Request) async throws -> HTTPStatus {
        guard let name = req.parameters.get("name"),
              !name.isEmpty else {
            throw Abort(.notFound, reason: "Automation name not provided")
        }

        await req.application.homeAutomationConfigService.setAutomationActive(with: name, to: false)
        return .ok
    }
}

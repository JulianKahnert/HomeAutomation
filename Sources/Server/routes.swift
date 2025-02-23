import HAImplementations
import HAModels
import OpenAPIVapor
import Vapor

func routes(_ app: Application) throws {
    app.get { _ async in
        "It works!"
    }

    app.get("config") { req in
        let location = await req.application.homeAutomationConfigService.location
        let automations = await req.application.homeAutomationConfigService.automations.map(AnyAutomation.create(from:))

        return ConfigDTO(location: location, automations: automations)
    }

    app.post("config") { req in
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

    let requestInjectionMiddleware = OpenAPIRequestInjectionMiddleware()
    let transport = VaporTransport(routesBuilder: app.grouped(requestInjectionMiddleware))

    let handler = ConfigController()
    try handler.registerHandlers(on: transport)
}

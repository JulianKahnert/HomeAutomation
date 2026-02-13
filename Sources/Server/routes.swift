import HAImplementations
import HAModels
import OpenAPIVapor
import SQLKit
import Vapor

func routes(_ app: Application) throws {
    // Create auth middleware
    let authMiddleware = TokenAuthenticationMiddleware(
        expectedToken: app.authToken,
        isAuthDisabled: app.authDisabled
    )

    // Apply auth to ALL routes
    let authenticatedRoutes = app.grouped(authMiddleware)

    // Manual routes - now protected
    authenticatedRoutes.get { _ async in
        "It works!"
    }

    authenticatedRoutes.get("health") { req async throws -> HTTPStatus in
        guard let sql = req.db as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL queries")
        }
        try await sql.raw("SELECT 1").run()
        return .ok
    }

    authenticatedRoutes.get("config") { req in
        let location = await req.application.homeAutomationConfigService.location
        let automations = await req.application.homeAutomationConfigService.automations.map(AnyAutomation.create(from:))

        return ConfigDTO(location: location, automations: automations)
    }

    authenticatedRoutes.on(.POST, "config", body: .collect(maxSize: "10mb")) { req in
        let configDTO = try req.content.decode(ConfigDTO.self)
        let skipValidation = req.query["skipValidation"] == "true"

        if !skipValidation {
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

    // OpenAPI routes - now protected with BOTH auth + request injection
    let requestInjectionMiddleware = OpenAPIRequestInjectionMiddleware()
    let transport = VaporTransport(
        routesBuilder: authenticatedRoutes.grouped(requestInjectionMiddleware)
    )

    let handler = OpenAPIController()
    try handler.registerHandlers(on: transport)
}

import HAApplicationLayer
import HAImplementations
import HAModels
import OpenAPIVapor
import Shared
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
    // Adapter WebSocket transport for the StarActorSystem (see ADR-001 in the knowledge base)
    registerAdapterWebSocket(on: authenticatedRoutes, system: app.starActorSystem)

    registerHealthRoute(on: authenticatedRoutes)

    authenticatedRoutes.get("config") { req in
        try await req.application.configReader.load()
    }

    authenticatedRoutes.on(.POST, "config", body: .collect(maxSize: "10mb")) { req in
        let configDTO = try req.content.decode(ConfigDTO.self)
        let skipValidation = req.query["skipValidation"] == "true"

        // The command port validates the entities (unless skipped) and deploys in its turn in the event loop.
        do {
            try await req.application.commandPort.deploy(configDTO.automations.map(\.automation), location: configDTO.location, skipValidation: skipValidation)
        } catch let error as CoreCommandError {
            switch error {
            case .unknownEntities(let missingEntityIds):
                throw Abort(.unprocessableEntity, reason: "Validation failed - Could not find the following entities: \(missingEntityIds)")
            case .timedOut:
                throw Abort(.serviceUnavailable, reason: "The server core did not answer in time")
            default:
                throw error
            }
        }

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

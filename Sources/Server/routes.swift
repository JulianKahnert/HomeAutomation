import HAApplicationLayer
import HAImplementations
import HAModels
import OpenAPIRuntime
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

        // The command port validates the entities (unless skipped) and deploys in its turn in the event loop; its
        // errors answer as `CoreCommandError` says (422 unknown entities, 503 busy).
        try await req.application.commandPort.deploy(configDTO.automations.map(\.automation), location: configDTO.location, skipValidation: skipValidation)

        return configDTO
    }

    // OpenAPI routes - now protected with BOTH auth + request injection
    let requestInjectionMiddleware = OpenAPIRequestInjectionMiddleware()
    let transport = VaporTransport(
        routesBuilder: authenticatedRoutes.grouped(requestInjectionMiddleware)
    )

    let handler = OpenAPIController()
    try handler.registerHandlers(on: transport, middlewares: [ErrorHandlingMiddleware()])
}

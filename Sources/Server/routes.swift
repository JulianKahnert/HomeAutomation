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

    // Adapter WebSocket transport for the StarActorSystem (see ADR-001 in the knowledge base)
    registerAdapterWebSocket(on: authenticatedRoutes, system: app.starActorSystem)

    authenticatedRoutes.get("health") { req async throws -> Response in
        guard let sql = req.db as? any SQLDatabase else {
            throw Abort(.internalServerError, reason: "Database does not support SQL queries")
        }
        let system = req.application.starActorSystem
        let homeManager = req.application.homeManager
        let scheduler = req.application.scheduler
        let automationService = req.application.automationService
        let gauge = req.application.eventLoopGauge

        // Race the health checks against a hard timeout so the Docker healthcheck always gets a
        // fast, definitive answer (503 peer-not-up / 504 timeout) instead of hanging.
        return try await withThrowingTaskGroup(of: Response.self) { group in
            group.addTask {
                try await sql.raw("SELECT 1").run()

                let connectionStatus = system.latestConnectionStatus
                guard connectionStatus == .up else {
                    throw Abort(.serviceUnavailable, reason: "Adapter connection status: \(connectionStatus.rawValue)")
                }

                // The link can stay up while macOS has cut the adapter off from HomeKit.
                if case .degraded(let reason) = await homeManager.homeKitHealth() {
                    throw Abort(.serviceUnavailable, reason: "HomeKit degraded: \(reason)")
                }
                // Last success per scheduled job, so a dead source is visible (nil until first success).
                let jobs = await scheduler?.lastSuccesses ?? [:]
                let body = HealthDTO(jobs: jobs.mapValues { $0.formatted(.iso8601) },
                                     loopAgeSeconds: await gauge?.age() ?? 0,
                                     laneAgeSeconds: await automationService.laneAges(),
                                     lastReports: await homeManager.lastReports().mapValues { $0.formatted(.iso8601) })
                let response = Response(status: .ok)
                try response.content.encode(body, as: .json)
                return response
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw Abort(.gatewayTimeout, reason: "Health check timed out")
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw Abort(.internalServerError)
            }
            return result
        }
    }

    authenticatedRoutes.get("config") { req in
        let location = await req.application.homeAutomationConfigService.location
        let automations = await req.application.automationService.automations.map(AnyAutomation.create(from:))

        return ConfigDTO(location: location, automations: automations)
    }

    authenticatedRoutes.on(.POST, "config", body: .collect(maxSize: "10mb")) { req in
        let configDTO = try req.content.decode(ConfigDTO.self)
        let skipValidation = req.query["skipValidation"] == "true"

        // validate if all automations are correct, e.g. contain existing entities
        let configEntityIds = configDTO.automations
            .map(\.automation)
            .flatMap { $0.getEntityIds() }
            .reduce(into: Set<EntityId>()) { partialResult, entityId in
                partialResult.insert(entityId)
            }

        if skipValidation {
            // Deliberate escape hatch for deploying a config before all devices exist in
            // HomeKit (or while the adapter is offline). It must never be silent: automations
            // referencing unknown entities fail at runtime and flood the critical-log notifier.
            req.logger.warning("⚠️ Accepting config with skipValidation=true - \(configEntityIds.count) referenced entities were NOT validated against HomeKit")
        } else {
            // A server-owned entity is not in HomeKit, so the adapter cannot confirm it (ADR-009); with nothing
            // else to check the adapter need not be online either.
            let homeKitEntityIds = configEntityIds.filter { !$0.isServerOwned }
            var missingEntityIds = homeKitEntityIds
            if !homeKitEntityIds.isEmpty {
                let foundEntityIds = try await req.application.homeManager.getAllEntitiesLive()
                missingEntityIds.subtract(foundEntityIds.map(\.entityId))
            }
            guard missingEntityIds.isEmpty else {
                throw Abort(.unprocessableEntity, reason: "Validation failed - Could not find the following entities: \(missingEntityIds)")
            }
        }

        await req.application.homeAutomationConfigService.set(location: configDTO.location)
        try await req.application.automationService.deploy(configDTO.automations.map(\.automation))
        // After the config is stored, so automations that react see the new one.
        req.application.homeEventsContinuation.yield(.configDeployed)

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

/// Body of `GET /health`: the last success of every scheduled job (ISO 8601) and the ages of the event loop and every lane.
struct HealthDTO: Content {
    let jobs: [String: String]
    /// How long the event loop has been on its current event.
    let loopAgeSeconds: Double
    /// Per automation: the age of the oldest event its lane has not finished checking; 0 when idle.
    let laneAgeSeconds: [String: Double]
    /// Per reporting source (`homekit`, `server`, a job name): when it last reported, a replay included (ISO 8601).
    /// A source is missing after a restart until its first report.
    let lastReports: [String: String]
}

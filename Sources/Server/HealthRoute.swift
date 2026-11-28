import HAApplicationLayer
import HAImplementations
import HAModels
import Shared
import SQLKit
import Vapor

/// `GET /health` is the one route that looks into the core: it answers whether the process works, not what the house holds.
func registerHealthRoute(on routes: any RoutesBuilder) {
    routes.get("health") { req async throws -> Response in
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
        // Not a task group: it waits for every child, and a stuck query does not react to cancellation.
        return try await raceTimeout(.seconds(5), timeoutError: { Abort(.gatewayTimeout, reason: "Health check timed out") }, operation: {
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
                                 loopAgeSeconds: gauge.age(),
                                 laneAgeSeconds: await automationService.laneAges(),
                                 lastReports: await homeManager.lastReports().mapValues { $0.formatted(.iso8601) })
            let response = Response(status: .ok)
            try response.content.encode(body, as: .json)
            return response
        })
    }
}

/// Body of `GET /health`: the last success of every scheduled job (ISO 8601) and the ages of the event loop and every lane.
struct HealthDTO: Content {
    let jobs: [String: String]
    /// The age of the oldest event the event loop has not finished, in the stream or being handled; 0 when idle.
    let loopAgeSeconds: Double
    /// Per automation: the age of the oldest event its lane has not finished checking; 0 when idle.
    let laneAgeSeconds: [String: Double]
    /// Per reporting source (`homekit`, `server`, a job name): when it last reported, a replay included (ISO 8601).
    /// A source is missing after a restart until its first report.
    let lastReports: [String: String]
}

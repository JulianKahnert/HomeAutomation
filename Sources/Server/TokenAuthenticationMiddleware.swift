//
//  TokenAuthenticationMiddleware.swift
//  HomeAutomation
//
//  Created by Claude Code on 27.01.26.
//

import Vapor

struct TokenAuthenticationMiddleware: AsyncMiddleware {
    private let expectedToken: String
    private let isAuthDisabled: Bool

    init(expectedToken: String, isAuthDisabled: Bool) {
        self.expectedToken = expectedToken
        self.isAuthDisabled = isAuthDisabled
    }

    func respond(
        to request: Request,
        chainingTo responder: AsyncResponder
    ) async throws -> Response {
        // Skip authentication if disabled (DEBUG mode only)
        guard !isAuthDisabled else {
            return try await responder.respond(to: request)
        }

        // Extract and validate token
        let providedToken = extractToken(from: request)
        guard let providedToken = providedToken, providedToken == expectedToken else {
            request.logger.warning("Authentication failed for \(request.method) \(request.url.path)")
            throw Abort(.unauthorized, reason: "Invalid or missing authentication token")
        }

        return try await responder.respond(to: request)
    }

    private func extractToken(from request: Request) -> String? {
        // Check Authorization: Bearer <token>
        if let authHeader = request.headers[.authorization].first {
            if authHeader.hasPrefix("Bearer ") {
                return String(authHeader.dropFirst(7))
            }
        }

        // Check X-API-Token: <token>
        return request.headers["X-API-Token"].first
    }
}

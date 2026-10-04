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
        guard let providedToken = providedToken, Self.constantTimeEquals(providedToken, expectedToken) else {
            request.logger.warning("Authentication failed for \(request.method) \(request.url.path)")
            throw Abort(.unauthorized, reason: "Invalid or missing authentication token")
        }

        return try await responder.respond(to: request)
    }

    private func extractToken(from request: Request) -> String? {
        // Check Authorization: Bearer <token>
        guard let authHeader = request.headers[.authorization].first,
              authHeader.hasPrefix("Bearer ") else {
            return nil
        }
        return String(authHeader.dropFirst(7))
    }

    /// Compares two tokens in time independent of where (or whether) they differ.
    ///
    /// Swift's `==` on `String` returns as soon as the first mismatching byte is found, which
    /// leaks how many leading bytes of a guess were correct through response latency. The
    /// endpoint is reachable from the public internet, so the comparison must not short-circuit.
    /// The loop always runs over the longer of the two inputs and folds the length difference
    /// into the result, so the only observable cost is proportional to the longer input.
    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let lhsBytes = Array(lhs.utf8)
        let rhsBytes = Array(rhs.utf8)
        var difference = lhsBytes.count ^ rhsBytes.count
        for index in 0..<max(lhsBytes.count, rhsBytes.count) {
            let lhsByte = index < lhsBytes.count ? lhsBytes[index] : 0
            let rhsByte = index < rhsBytes.count ? rhsBytes[index] : 0
            difference |= Int(lhsByte ^ rhsByte)
        }
        return difference == 0
    }
}

//
//  TokenAuthenticationTests.swift
//  HomeAutomation
//
//  Created by Claude Code on 27.01.26.
//

@testable import Server
import XCTVapor

final class TokenAuthenticationTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        app = try await Application.make(.testing)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    // MARK: - Valid Authentication Tests

    func testValidBearerTokenAuthentication() async throws {
        // Setup
        let testToken = "test-secure-token-123"
        app.authToken = testToken
        app.authDisabled = false

        let authMiddleware = TokenAuthenticationMiddleware(
            expectedToken: testToken,
            isAuthDisabled: false
        )

        app.grouped(authMiddleware).get("test") { _ in "Success" }

        // Test
        try await app.test(.GET, "/test", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer \(testToken)")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Success")
        })
    }

    // MARK: - Invalid Authentication Tests

    func testMissingTokenReturns401() async throws {
        // Setup
        let testToken = "test-secure-token-789"
        app.authToken = testToken
        app.authDisabled = false

        let authMiddleware = TokenAuthenticationMiddleware(
            expectedToken: testToken,
            isAuthDisabled: false
        )

        app.grouped(authMiddleware).get("test") { _ in "Success" }

        // Test - no token provided
        try await app.test(.GET, "/test", afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
            XCTAssertTrue(res.body.string.contains("Invalid or missing authentication token"))
        })
    }

    func testInvalidBearerTokenReturns401() async throws {
        // Setup
        let testToken = "correct-token"
        app.authToken = testToken
        app.authDisabled = false

        let authMiddleware = TokenAuthenticationMiddleware(
            expectedToken: testToken,
            isAuthDisabled: false
        )

        app.grouped(authMiddleware).get("test") { _ in "Success" }

        // Test - wrong token
        try await app.test(.GET, "/test", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer wrong-token")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
            XCTAssertTrue(res.body.string.contains("Invalid or missing authentication token"))
        })
    }

    func testMalformedAuthorizationHeaderReturns401() async throws {
        // Setup
        let testToken = "correct-token"
        app.authToken = testToken
        app.authDisabled = false

        let authMiddleware = TokenAuthenticationMiddleware(
            expectedToken: testToken,
            isAuthDisabled: false
        )

        app.grouped(authMiddleware).get("test") { _ in "Success" }

        // Test - malformed header (missing "Bearer " prefix)
        try await app.test(.GET, "/test", beforeRequest: { req in
            req.headers.add(name: .authorization, value: testToken)
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })
    }

    // MARK: - Authentication Disabled Tests

    func testAuthDisabledAllowsAccessWithoutToken() async throws {
        // Setup
        let testToken = "test-token"
        app.authToken = testToken
        app.authDisabled = true

        let authMiddleware = TokenAuthenticationMiddleware(
            expectedToken: testToken,
            isAuthDisabled: true
        )

        app.grouped(authMiddleware).get("test") { _ in "Success" }

        // Test - no token but auth disabled
        try await app.test(.GET, "/test", afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Success")
        })
    }

    func testAuthDisabledIgnoresInvalidToken() async throws {
        // Setup
        let testToken = "correct-token"
        app.authToken = testToken
        app.authDisabled = true

        let authMiddleware = TokenAuthenticationMiddleware(
            expectedToken: testToken,
            isAuthDisabled: true
        )

        app.grouped(authMiddleware).get("test") { _ in "Success" }

        // Test - wrong token but auth disabled
        try await app.test(.GET, "/test", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer wrong-token")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Success")
        })
    }

    // MARK: - Multiple Endpoints Tests

    func testAuthenticationRequiredForMultipleRoutes() async throws {
        // Setup
        let testToken = "multi-route-token"
        app.authToken = testToken
        app.authDisabled = false

        let authMiddleware = TokenAuthenticationMiddleware(
            expectedToken: testToken,
            isAuthDisabled: false
        )

        let protected = app.grouped(authMiddleware)
        protected.get("route1") { _ in "Route 1" }
        protected.get("route2") { _ in "Route 2" }
        protected.post("route3") { _ in "Route 3" }

        // Test route1 - authenticated
        try await app.test(.GET, "/route1", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer \(testToken)")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Route 1")
        })

        // Test route2 - unauthenticated
        try await app.test(.GET, "/route2", afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })

        // Test route3 - authenticated POST
        try await app.test(.POST, "/route3", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer \(testToken)")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "Route 3")
        })
    }

    // MARK: - Edge Cases

    func testEmptyBearerTokenReturns401() async throws {
        // Setup
        let testToken = "test-token"
        app.authToken = testToken
        app.authDisabled = false

        let authMiddleware = TokenAuthenticationMiddleware(
            expectedToken: testToken,
            isAuthDisabled: false
        )

        app.grouped(authMiddleware).get("test") { _ in "Success" }

        // Test - empty token after "Bearer "
        try await app.test(.GET, "/test", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer ")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })
    }

    func testTokenWithWhitespaceIsNotTrimmed() async throws {
        // Setup - tokens should be exact match, no trimming
        let testToken = "test-token"
        app.authToken = testToken
        app.authDisabled = false

        let authMiddleware = TokenAuthenticationMiddleware(
            expectedToken: testToken,
            isAuthDisabled: false
        )

        app.grouped(authMiddleware).get("test") { _ in "Success" }

        // Test - token with extra whitespace should fail
        try await app.test(.GET, "/test", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer \(testToken) ")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })
    }

    func testCaseSensitiveTokenComparison() async throws {
        // Setup
        let testToken = "TestToken123"
        app.authToken = testToken
        app.authDisabled = false

        let authMiddleware = TokenAuthenticationMiddleware(
            expectedToken: testToken,
            isAuthDisabled: false
        )

        app.grouped(authMiddleware).get("test") { _ in "Success" }

        // Test - different case should fail
        try await app.test(.GET, "/test", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer testtoken123")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })

        // Test - exact case should succeed
        try await app.test(.GET, "/test", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer TestToken123")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
        })
    }
}

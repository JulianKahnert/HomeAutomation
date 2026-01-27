//
//  AuthenticationIntegrationTests.swift
//  HomeAutomation
//
//  Created by Claude Code on 27.01.26.
//
//  Integration tests for authentication with the full app configuration

@testable import HAImplementations
@testable import HAModels
@testable import Server
import XCTVapor

final class AuthenticationIntegrationTests: XCTestCase {
    var app: Application!

    override func setUp() async throws {
        app = try await Application.make(.testing)

        // Set required environment variables for testing
        app.environment.arguments = ["serve"]

        // Configure auth for testing
        app.authToken = "test-integration-token-123"
        app.authDisabled = false

        // Mock homeAutomationConfigService for testing
        let mockLocation = Location(latitude: 52.52, longitude: 13.405)
        app.homeAutomationConfigService = HomeAutomationConfigService(location: mockLocation, automations: [])

        // Register routes (this applies the authentication middleware)
        try routes(app)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    // MARK: - Root Endpoint Tests

    func testRootEndpointRequiresAuthentication() async throws {
        // Test without token - should fail
        try await app.test(.GET, "/", afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
            XCTAssertTrue(res.body.string.contains("Invalid or missing authentication token"))
        })
    }

    func testRootEndpointWithValidToken() async throws {
        // Test with valid token - should succeed
        try await app.test(.GET, "/", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer test-integration-token-123")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "It works!")
        })
    }

    func testRootEndpointWithInvalidToken() async throws {
        // Test with wrong token - should fail
        try await app.test(.GET, "/", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer wrong-token")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })
    }

    // MARK: - Config Endpoint Tests

    func testConfigGetRequiresAuthentication() async throws {
        // Test without token - should fail
        try await app.test(.GET, "/config", afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })
    }

    func testConfigGetWithValidToken() async throws {
        // Test with valid token - should succeed
        try await app.test(.GET, "/config", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer test-integration-token-123")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
            // Should return JSON with location and automations
            XCTAssertTrue(res.headers.contentType?.description.contains("application/json") ?? false)
        })
    }

    func testConfigPostRequiresAuthentication() async throws {
        // Test without token - should fail
        let configJSON = """
        {
            "location": {
                "latitude": 52.52,
                "longitude": 13.405,
                "timeZone": "Europe/Berlin"
            },
            "automations": []
        }
        """

        try await app.test(.POST, "/config", beforeRequest: { req in
            req.headers.contentType = .json
            req.body = ByteBuffer(string: configJSON)
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })
    }

    func testConfigPostWithValidToken() async throws {
        // Test with valid token - should succeed
        let configJSON = """
        {
            "location": {
                "latitude": 52.52,
                "longitude": 13.405,
                "timeZone": "Europe/Berlin"
            },
            "automations": []
        }
        """

        try await app.test(.POST, "/config?skipValidation=true", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer test-integration-token-123")
            req.headers.contentType = .json
            req.body = ByteBuffer(string: configJSON)
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
        })
    }

    // MARK: - Multiple Endpoints Test

    func testMultipleEndpointsAllProtected() async throws {
        let endpoints: [(HTTPMethod, String)] = [
            (.GET, "/"),
            (.GET, "/config"),
            (.POST, "/config")
        ]

        for (method, path) in endpoints {
            // Test each endpoint without token - all should fail
            try await app.test(method, path, afterResponse: { res async in
                XCTAssertEqual(
                    res.status,
                    .unauthorized,
                    "\(method) \(path) should require authentication"
                )
            })
        }
    }

    // MARK: - Auth Disabled Mode Tests

    func testAuthDisabledAllowsAccessWithoutToken() async throws {
        // Create new app with auth disabled
        let testApp = try await Application.make(.testing)
        testApp.authToken = "any-token"
        testApp.authDisabled = true
        try routes(testApp)

        // Should work without token when auth is disabled
        try await testApp.test(.GET, "/", afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
            XCTAssertEqual(res.body.string, "It works!")
        })

        try await testApp.asyncShutdown()
    }

    // MARK: - Error Message Tests

    func testUnauthorizedErrorMessageIsClear() async throws {
        try await app.test(.GET, "/", afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
            let errorMessage = res.body.string
            XCTAssertTrue(
                errorMessage.contains("authentication"),
                "Error message should mention authentication"
            )
            XCTAssertTrue(
                errorMessage.contains("token"),
                "Error message should mention token"
            )
        })
    }

    // MARK: - Case Sensitivity Tests

    func testTokenIsCaseSensitive() async throws {
        // Test with wrong case - should fail
        try await app.test(.GET, "/", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer TEST-INTEGRATION-TOKEN-123")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })

        // Test with correct case - should succeed
        try await app.test(.GET, "/", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer test-integration-token-123")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
        })
    }

    // MARK: - Whitespace Tests

    func testTokenWithWhitespaceIsRejected() async throws {
        // Test with leading whitespace
        try await app.test(.GET, "/", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer  test-integration-token-123")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })

        // Test with trailing whitespace
        try await app.test(.GET, "/", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer test-integration-token-123 ")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })

        // Test exact token - should succeed
        try await app.test(.GET, "/", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer test-integration-token-123")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
        })
    }
}

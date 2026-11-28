//
//  AuthenticationIntegrationTests.swift
//  HomeAutomation
//
//  Created by Claude Code on 27.01.26.
//
//  Integration tests for authentication with the full app configuration

import HAApplicationLayer
@testable import HAImplementations
@testable import HAModels
@testable import Server
import StarActorSystem
import XCTVapor

final class AuthenticationIntegrationTests: XCTestCase {
    var app: Application!
    private var loop: Task<Void, Never>!

    override func setUp() async throws {
        app = try await Application.make(.testing)

        // Set required environment variables for testing
        app.environment.arguments = ["serve"]

        // Configure auth for testing
        app.authToken = "test-integration-token-123"
        app.authDisabled = false

        // Mock homeAutomationConfigService for testing
        let mockLocation = Location(latitude: 52.52, longitude: 13.405)
        app.homeAutomationConfigService = HomeAutomationConfigService(location: mockLocation, persist: { _ in })
        app.automationService = try await makeAutomationService(automations: [])
        app.configReader = StoredConfig(config: ConfigDTO(location: mockLocation, automations: []))
        app.homeManager = await HomeManager(getAdapter: { nil }, storageRepo: EmptyStorage(), notificationSender: SilentSender(), location: mockLocation)
        loop = app.startEventLoop()

        // The WebSocket route registration needs an actor system present
        app.starActorSystem = StarActorSystem(name: "server-tests")

        // Register routes (this applies the authentication middleware)
        try routes(app)
    }

    override func tearDown() async throws {
        loop.cancel()
        try await app.asyncShutdown()
        app = nil
    }

    // MARK: - Config Endpoint Tests

    func testConfigEndpointRequiresAuthentication() async throws {
        // Test without token - should fail
        try await app.test(.GET, "/config", afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
            XCTAssertTrue(res.body.string.contains("Invalid or missing authentication token"))
        })
    }

    func testConfigEndpointWithValidToken() async throws {
        // Test with valid token - should succeed
        try await app.test(.GET, "/config", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer test-integration-token-123")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
        })
    }

    func testConfigEndpointWithInvalidToken() async throws {
        // Test with wrong token - should fail
        try await app.test(.GET, "/config", beforeRequest: { req in
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
        testApp.starActorSystem = StarActorSystem(name: "server-tests")
        testApp.homeAutomationConfigService = HomeAutomationConfigService(location: Location(latitude: 52.52, longitude: 13.405), persist: { _ in })
        testApp.automationService = try await makeAutomationService(automations: [])
        testApp.configReader = StoredConfig(config: ConfigDTO(location: Location(latitude: 52.52, longitude: 13.405), automations: []))
        try routes(testApp)

        // Should work without token when auth is disabled
        try await testApp.test(.GET, "/config", afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
        })

        try await testApp.asyncShutdown()
    }

    // MARK: - Error Message Tests

    func testUnauthorizedErrorMessageIsClear() async throws {
        try await app.test(.GET, "/config", afterResponse: { res async in
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
        try await app.test(.GET, "/config", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer TEST-INTEGRATION-TOKEN-123")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })

        // Test with correct case - should succeed
        try await app.test(.GET, "/config", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer test-integration-token-123")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
        })
    }

    // MARK: - Whitespace Tests

    func testTokenWithWhitespaceIsRejected() async throws {
        // Test with leading whitespace
        try await app.test(.GET, "/config", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer  test-integration-token-123")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })

        // Test with trailing whitespace
        try await app.test(.GET, "/config", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer test-integration-token-123 ")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .unauthorized)
        })

        // Test exact token - should succeed
        try await app.test(.GET, "/config", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer test-integration-token-123")
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
        })
    }

    // MARK: - Config deploy hook

    func testPostingAConfigEntersTheEventLoopAsADeployCommand() async throws {
        let (stream, continuation) = AsyncStream.makeStream(of: HomeInput.self)
        app.homeEventsStream = stream
        app.homeEventsContinuation = continuation
        let body = try JSONEncoder().encode(ConfigDTO(location: Location(latitude: 1, longitude: 2), automations: []))
        // stands in for the event loop: takes the deploy command and answers it
        let loop = Task { () -> [String] in
            var names: [String] = []
            for await input in stream {
                guard case .write(let command) = input else { continue }
                names.append(command.kind.name)
                command.complete(.success(nil))
                break
            }
            return names
        }

        try await app.test(.POST, "/config?skipValidation=true", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer test-integration-token-123")
            req.headers.contentType = .json
            req.body = ByteBuffer(data: body)
        }, afterResponse: { res async in
            XCTAssertEqual(res.status, .ok)
        })

        let names = await loop.value
        XCTAssertEqual(names, ["deploy"])
    }
}

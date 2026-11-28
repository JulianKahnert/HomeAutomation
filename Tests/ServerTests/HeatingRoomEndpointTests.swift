//
//  HeatingRoomEndpointTests.swift
//  HomeAutomationServer
//

import HAApplicationLayer
@testable import HAImplementations
@testable import HAModels
@testable import Server
import StarActorSystem
import XCTVapor

final class HeatingRoomEndpointTests: XCTestCase {
    var app: Application!
    private let token = "heating-test-token"

    override func setUp() async throws {
        app = try await Application.make(.testing)
        app.environment.arguments = ["serve"]
        app.authToken = token
        app.authDisabled = false
        let room = RoomHeating("Bad", placeId: "Bad - OG",
                               radiators: [Radiator(query: .init(placeId: "Bad - OG", name: "Thermo"))],
                               configuration: HeatingConfiguration(standardPlan: HeatingPlan([])))
        app.homeAutomationConfigService = HomeAutomationConfigService(location: Location(latitude: 52.52, longitude: 13.405), persist: { _ in })
        app.configReader = StoredConfig(config: ConfigDTO(location: Location(latitude: 52.52, longitude: 13.405), automations: [AnyAutomation.create(from: room)]))
        app.storageReader = MemoryStorage()
        app.journalReader = InMemoryJournalStore()
        app.starActorSystem = StarActorSystem(name: "heating-tests")
        try routes(app)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    private func get(_ path: String, token: String? = nil) async throws -> HTTPStatus {
        var status: HTTPStatus = .internalServerError
        try await app.test(.GET, path, beforeRequest: { req in
            if let token { req.headers.add(name: .authorization, value: "Bearer \(token)") }
        }, afterResponse: { res async in status = res.status })
        return status
    }

    func testUnknownRangeAnswers400() async throws {
        let status = try await get("/heating/rooms/Bad%20-%20OG?range=3h", token: token)
        XCTAssertEqual(status, .badRequest)
    }

    func testUnknownRoomAnswers404() async throws {
        let status = try await get("/heating/rooms/Keller?range=24h", token: token)
        XCTAssertEqual(status, .notFound)
    }

    func testRoomEndpointRequiresAuthentication() async throws {
        let status = try await get("/heating/rooms/Bad%20-%20OG")
        XCTAssertEqual(status, .unauthorized)
    }

    func testOverviewRequiresAuthentication() async throws {
        let status = try await get("/heating/overview")
        XCTAssertEqual(status, .unauthorized)
    }
}

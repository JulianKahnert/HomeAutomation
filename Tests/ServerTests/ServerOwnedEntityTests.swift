//
//  ServerOwnedEntityTests.swift
//  HomeAutomationServer
//

import Foundation
import HAApplicationLayer
@testable import HAImplementations
@testable import HAModels
@testable import Server
import StarActorSystem
import XCTVapor

final class ServerOwnedEntityTests: XCTestCase {
    var app: Application!
    private let token = "server-owned-test-token"

    override func setUp() async throws {
        app = try await Application.make(.testing)
        app.environment.arguments = ["serve"]
        app.authToken = token
        app.authDisabled = false
        app.homeAutomationConfigService = HomeAutomationConfigService(location: Location(latitude: 52.52, longitude: 13.405), persist: { _ in })
        app.automationService = try await makeAutomationService(automations: [])
        app.starActorSystem = StarActorSystem(name: "server-owned-tests")
        let (stream, continuation) = AsyncStream.makeStream(of: HomeEvent.self)
        app.homeEventsStream = stream
        app.homeEventsContinuation = continuation
        // no adapter: a server-owned entity needs none, a HomeKit entity cannot be checked
        app.homeManager = await HomeManager(getAdapter: { nil },
                                            storageRepo: EmptyStorage(),
                                            notificationSender: SilentSender(),
                                            location: Location(latitude: 52.52, longitude: 13.405))
        try routes(app)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    private func deploy(naming entityId: EntityId) async throws -> HTTPStatus {
        let window = WindowOpen("window", windowContact: ContactSensorDevice(contactSensorId: entityId, batterySensorId: nil))
        let dto = ConfigDTO(location: Location(latitude: 52.52, longitude: 13.405), automations: [AnyAutomation.create(from: window)])
        let body = try JSONEncoder().encode(dto)
        var status: HTTPStatus = .internalServerError
        try await app.test(.POST, "/config", beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
            req.headers.contentType = .json
            req.body = ByteBuffer(data: body)
        }, afterResponse: { res async in status = res.status })
        return status
    }

    func testDeployAcceptsAConfigThatNamesAServerOwnedEntity() async throws {
        let status = try await deploy(naming: .serverOwned(name: "holiday", characteristic: .contactSensor))
        XCTAssertEqual(status, .ok)
    }

    func testDeployStillChecksAHomeKitEntity() async throws {
        let status = try await deploy(naming: EntityId(placeId: "room", name: "contact", characteristicsName: nil, characteristic: .contactSensor))
        XCTAssertNotEqual(status, .ok)
    }

    func testOnlyOriginsThatCheckedAtTheSourceSkipTheLoopCheck() {
        XCTAssertTrue(Origin.server.isCheckedAtSource)
        XCTAssertTrue(Origin.app.isCheckedAtSource)
        XCTAssertFalse(Origin.homekit.isCheckedAtSource)
        XCTAssertFalse(Origin.job("ValveJob").isCheckedAtSource)
    }
}

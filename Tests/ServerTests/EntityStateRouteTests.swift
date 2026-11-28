//
//  EntityStateRouteTests.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAApplicationLayer
@testable import HAImplementations
@testable import HAModels
@testable import Server
import StarActorSystem
import XCTVapor

final class EntityStateRouteTests: XCTestCase {
    var app: Application!
    private var loop: Task<Void, Never>!
    private let token = "entity-state-test-token"
    private let settable = EntityId.serverOwned(name: "fireplace", characteristic: .switcher)

    override func setUp() async throws {
        app = try await Application.make(.testing)
        app.environment.arguments = ["serve"]
        app.authToken = token
        app.authDisabled = false
        app.homeAutomationConfigService = HomeAutomationConfigService(location: Location(latitude: 52.52, longitude: 13.405), persist: { _ in })
        app.automationService = try await makeAutomationService(automations: [])
        app.starActorSystem = StarActorSystem(name: "entity-state-tests")
        app.databases.use(InMemoryDatabaseConfiguration(), as: DatabaseID(string: "in-memory"), isDefault: true)
        app.homeManager = await HomeManager(getAdapter: { nil },
                                            storageRepo: MemoryStorage(),
                                            notificationSender: SilentSender(),
                                            location: Location(latitude: 52.52, longitude: 13.405),
                                            onReportedChange: { [app] in app?.homeEventSink.yield(.change(entity: $0)) })
        loop = app.startEventLoop()
        try routes(app)
    }

    override func tearDown() async throws {
        loop.cancel()
        try await app.asyncShutdown()
        app = nil
    }

    private func put(_ json: String, authorized: Bool = true) async throws -> (HTTPStatus, [String: Any]) {
        var status: HTTPStatus = .internalServerError
        var object: [String: Any] = [:]
        try await app.test(.PUT, "/entities/state", beforeRequest: { req in
            if authorized { req.headers.add(name: .authorization, value: "Bearer \(token)") }
            req.headers.contentType = .json
            req.body = ByteBuffer(string: json)
        }, afterResponse: { res async in
            status = res.status
            object = (try? JSONSerialization.jsonObject(with: Data(res.body.readableBytesView))) as? [String: Any] ?? [:]
        })
        return (status, object)
    }

    private func body(placeId: String = "server", name: String = "fireplace", type: String = "switcher", value: String) -> String {
        #"{"entityId":{"placeId":"\#(placeId)","name":"\#(name)","characteristicType":"\#(type)"},"value":\#(value)}"#
    }

    func testSettingHoldsAtOnce() async throws {
        let (status, answer) = try await put(body(value: "true"))
        XCTAssertEqual(status, .ok)
        XCTAssertEqual(answer["value"] as? Bool, true)
        XCTAssertEqual(answer["changed"] as? Bool, true)
        XCTAssertEqual(answer["origin"] as? String, Origin.app.rawValue)
        let held = try await app.homeManager.getCurrentEntity(with: settable)
        XCTAssertEqual(held.value, .bool(true))
        XCTAssertEqual(held.origin, .app)
    }

    func testARepeatedValueChangesNothing() async throws {
        _ = try await put(body(value: "true"))
        let first = try await app.homeManager.getCurrentEntity(with: settable)
        let (status, answer) = try await put(body(value: "true"))
        XCTAssertEqual(status, .ok)
        XCTAssertEqual(answer["changed"] as? Bool, false)
        let second = try await app.homeManager.getCurrentEntity(with: settable)
        XCTAssertEqual(second.timestamp, first.timestamp)
    }

    func testAnEntityThatIsNotSettableIsRefusedAndUnchanged() async throws {
        // a server-owned kind the descriptor does not mark as settable
        let contact = EntityId.serverOwned(name: "holiday", characteristic: .contactSensor)
        var (status, _) = try await put(body(name: "holiday", type: "contactSensor", value: "true"))
        XCTAssertEqual(status, .forbidden)
        // a HomeKit entity
        (status, _) = try await put(body(placeId: "kitchen", name: "lamp", value: "true"))
        XCTAssertEqual(status, .forbidden)
        let unknown = try? await app.homeManager.getCurrentEntity(with: contact)
        XCTAssertNil(unknown)
        let homekit = try? await app.homeManager.getCurrentEntity(with: EntityId(placeId: "kitchen", name: "lamp", characteristicsName: nil, characteristic: .switcher))
        XCTAssertNil(homekit)
    }

    func testAServerOwnedEntityOfASettableKindIsAccepted() async throws {
        let target = EntityId.serverOwned(name: "livingRoom", characteristic: .targetTemperature)
        let (status, answer) = try await put(body(name: "livingRoom", type: "targetTemperature", value: "25"))
        XCTAssertEqual(status, .ok)
        XCTAssertEqual(answer["value"] as? Double, 25)
        let held = try await app.homeManager.getCurrentEntity(with: target)
        XCTAssertEqual(held.value, .number(25))
    }

    func testOnlySwitchHeatingModeAndTargetTemperatureAreSettableKinds() {
        let settable = CharacteristicsType.allCases.filter { ValueDescriptor.descriptor(for: $0).isSettableFromApp }
        XCTAssertEqual(Set(settable), [.switcher, .heatingMode, .targetTemperature])
    }

    func testAValueOfTheWrongShapeIsRefused() async throws {
        let (status, _) = try await put(body(value: "42"))
        XCTAssertEqual(status, .badRequest)
        let state = try? await app.homeManager.getCurrentEntity(with: settable)
        XCTAssertNil(state)
    }

    func testTheRouteRequiresTheToken() async throws {
        let (status, _) = try await put(body(value: "true"), authorized: false)
        XCTAssertEqual(status, .unauthorized)
        let state = try? await app.homeManager.getCurrentEntity(with: settable)
        XCTAssertNil(state)
    }
}

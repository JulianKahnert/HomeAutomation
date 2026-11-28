//
//  ThinApiLayerTests.swift
//  HomeAutomationServer
//

import Foundation
import HAApplicationLayer
@testable import HAImplementations
@testable import HAModels
@testable import Server
import StarActorSystem
import XCTVapor

/// T27: the API layer reads from storage, journal and config only, and writes through the command port.
final class ThinApiLayerTests: XCTestCase {
    var app: Application!
    private let token = "thin-api-test-token"
    private let opened = Date(timeIntervalSince1970: 1_800_000_000)
    private let room = RoomHeating("Bad", placeId: "Bad - OG",
                                   radiators: [Radiator(query: .init(placeId: "Bad - OG", name: "Thermo"))],
                                   configuration: HeatingConfiguration(standardPlan: HeatingPlan([])))

    /// Neither a `HomeManager` nor an `AutomationService` is set: touching one would crash the test.
    override func setUp() async throws {
        app = try await Application.make(.testing)
        app.environment.arguments = ["serve"]
        app.authToken = token
        app.authDisabled = false
        app.starActorSystem = StarActorSystem(name: "thin-api-tests")
        let window = EntityId.serverOwned(name: "Bad - OG/Fenster", characteristic: .deadline)
        let end = opened.addingTimeInterval(900)
        let storage = MemoryStorage(seed: [
            EntityStorageItem(entityId: window, timestamp: opened, deadline: .running(until: end), origin: .server),
            EntityStorageItem(entityId: .outdoorTemperature, timestamp: opened, temperatureInC: .init(value: 4, unit: .celsius), origin: .server),
            EntityStorageItem(entityId: Fireplace.stateId, timestamp: opened, isDeviceOn: true, origin: .app)
        ])
        app.storageReader = storage
        let running = AutomationRun(automationName: room.name, startedAt: opened, trigger: .init(kind: .time, entityId: nil, summary: "tick"), outcome: .running)
        let journal = InMemoryJournalStore()
        try await journal.add(running)
        app.journalReader = journal
        var inactive = DatabaseCleanup()
        inactive.isActive = false
        app.configReader = StoredConfig(config: ConfigDTO(location: Location(latitude: 52.52, longitude: 13.405),
                                                          automations: [AnyAutomation.create(from: room), AnyAutomation.create(from: inactive)]))
        try routes(app)
    }

    override func tearDown() async throws {
        try await app.asyncShutdown()
        app = nil
    }

    private func get(_ path: String) async throws -> (HTTPStatus, Data) {
        var status: HTTPStatus = .internalServerError
        var body = Data()
        try await app.test(.GET, path, beforeRequest: { req in
            req.headers.add(name: .authorization, value: "Bearer \(token)")
        }, afterResponse: { res async in
            status = res.status
            body = Data(res.body.readableBytesView)
        })
        return (status, body)
    }

    private func json(_ path: String) async throws -> Any {
        let (status, body) = try await get(path)
        XCTAssertEqual(status, .ok, String(decoding: body, as: UTF8.self))
        return try JSONSerialization.jsonObject(with: body)
    }

    func testConfigIsTheStoredOne() async throws {
        let config = try await json("/config") as? [String: Any]
        XCTAssertEqual((config?["automations"] as? [Any])?.count, 2)
        XCTAssertEqual((config?["location"] as? [String: Any])?["latitude"] as? Double, 52.52)
    }

    func testAutomationsComeFromTheStoredConfigAndTheJournal() async throws {
        let automationsJson = try await json("/config/automations")
        let automations = try XCTUnwrap(automationsJson as? [[String: Any]])
        let byName = Dictionary(uniqueKeysWithValues: automations.compactMap { entry in (entry["name"] as? String).map { ($0, entry) } })
        XCTAssertEqual(byName[room.name]?["isActive"] as? Bool, true)
        // a run the journal holds as running
        XCTAssertEqual(byName[room.name]?["isRunning"] as? Bool, true)
        XCTAssertNotNil(byName[room.name]?["lastRun"])
        XCTAssertEqual(byName["DatabaseCleanup"]?["isActive"] as? Bool, false)
        XCTAssertEqual(byName["DatabaseCleanup"]?["isRunning"] as? Bool, false)
    }

    func testRunsComeFromTheJournal() async throws {
        let runsJson = try await json("/config/automations/\(room.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")/runs")
        let runs = try XCTUnwrap(runsJson as? [[String: Any]])
        XCTAssertEqual(runs.count, 1)
    }

    func testWindowStatesAreComputedFromTheStoredDeadlines() async throws {
        let statesJson = try await json("/windowstates")
        let states = try XCTUnwrap(statesJson as? [String: Any])
        XCTAssertEqual(states["openCount"] as? Int, 1)
        XCTAssertEqual(states["outdoorTemperature"] as? Double, 4)
        let window = try XCTUnwrap((states["windowStates"] as? [[String: Any]])?.first)
        XCTAssertEqual(window["room"] as? String, "Bad - OG")
        XCTAssertEqual(window["name"] as? String, "Fenster")
    }

    func testFireplaceIsDerivedFromTheStoredEntity() async throws {
        let fireplaceJson = try await json("/heating/fireplace")
        let fireplace = try XCTUnwrap(fireplaceJson as? [String: Any])
        XCTAssertEqual(fireplace["isOn"] as? Bool, true)
        XCTAssertNotNil(fireplace["since"])
    }

    func testHeatingReadsTheRoomsOfTheStoredConfig() async throws {
        let overviewJson = try await json("/heating/overview")
        let overview = try XCTUnwrap(overviewJson as? [String: Any])
        XCTAssertEqual((overview["rooms"] as? [[String: Any]])?.count, 1)
        let detailJson = try await json("/heating/rooms/Bad%20-%20OG?range=24h")
        let detail = try XCTUnwrap(detailJson as? [String: Any])
        XCTAssertEqual(detail["placeId"] as? String, "Bad - OG")
    }

    func testHistoryAnswersFromStorage() async throws {
        let historyJson = try await json("/entities/history?placeId=server&name=fireplace&characteristicType=switcher")
        let history = try XCTUnwrap(historyJson as? [String: Any])
        XCTAssertEqual((history["items"] as? [Any])?.count, 1)
        let roomsJson = try await json("/entities/history/room?placeId=server")
        let rooms = try XCTUnwrap(roomsJson as? [[String: Any]])
        XCTAssertEqual(rooms.count, 3)
    }

    // MARK: - boundary

    /// The API layer knows the command port and the repositories, never the types or accessors of the core. It is every
    /// file that declares or extends `OpenAPIController`, plus the route registration; only `HealthRoute.swift` may
    /// touch the core. Comments are ignored.
    func testTheApiLayerReferencesNothingOfTheCore() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Server")
        let forbidden = ["HomeManager", "HomeManagable", "AutomationService", "homeManager", "automationService", "homeEventSink",
                         "homeEventsContinuation", "homeEventsStream", "scheduler", "homeAutomationConfigService",
                         "entityStorageDbRepository", "journalRepository", "eventLoopGauge"]
        var files = [sources.appendingPathComponent("routes.swift")]
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "swift" && url.lastPathComponent != "HealthRoute.swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("OpenAPIController") && !files.contains(url) { files.append(url) }
        }
        XCTAssertGreaterThanOrEqual(files.count, 2)
        for file in files {
            let code = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    var line = String(line)
                    if let range = line.range(of: "//") { line.removeSubrange(range.lowerBound...) }
                    return line
                }
                .joined(separator: "\n")
            for word in forbidden {
                XCTAssertFalse(code.contains(word), "\(file.lastPathComponent) references \(word)")
            }
        }
    }
}

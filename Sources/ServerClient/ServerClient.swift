//
//  ServerClient.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 26.02.25.
//

import Foundation
import HAModels
import Logging
import OpenAPIURLSession

public struct ServerClient {
    private static let logger = Logger(label: "ServerClient")
    private let client: Client
    private let url: URL
    private let session: URLSession

    public init(url: URL, authToken: String? = nil) {
        // Create URLSession with authentication header if token is provided
        let session: URLSession
        if let authToken = authToken, !authToken.isEmpty {
            let configuration = URLSessionConfiguration.default
            configuration.httpAdditionalHeaders = [
                "Authorization": "Bearer \(authToken)"
            ]
            session = URLSession(configuration: configuration)
        } else {
            session = URLSession.shared
        }

        self.url = url
        self.session = session
        self.client = Client(
            serverURL: url,
            transport: URLSessionTransport(configuration: .init(session: session))
        )
    }

    public func getAutomations() async throws -> [AutomationInfo] {
        let response = try await client.getAutomations()
        return try response.ok.body.json
            .map { automation in
                try AutomationInfo(name: automation.name,
                                   isActive: automation.isActive,
                                   isRunning: automation.isRunning,
                                   type: automation._type,
                                   recordsRuns: automation.recordsRuns ?? true,
                                   lastRun: automation.lastRun.map(AutomationRun.init),
                                   entities: (automation.entities ?? []).compactMap(EntityId.init))
            }
    }

    /// `true` when the server and its adapter connection are up. `GET /health` is not part of the
    /// OpenAPI spec because the Docker healthcheck owns it, so this calls it directly.
    public func isHealthy() async throws -> Bool {
        let (_, response) = try await session.data(from: url.appending(path: "health"))
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// The server's location from `GET /config`, which is not part of the OpenAPI spec because its
    /// automations are polymorphic JSON; only `location` is decoded.
    public func getLocation() async throws -> Location {
        struct Config: Decodable { let location: Location }
        let (data, response) = try await session.data(from: url.appending(path: "config"))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Config.self, from: data).location
    }

    public func getRuns(automation name: String, startDate: Date? = nil, endDate: Date? = nil, limit: Int? = nil) async throws -> [AutomationRun] {
        let response = try await client.getAutomationRuns(path: .init(name: name),
                                                          query: .init(startDate: startDate, endDate: endDate, limit: limit))
        return try response.ok.body.json.map(AutomationRun.init)
    }

    public func getRecentRuns(since date: Date, limit: Int? = nil) async throws -> [AutomationRun] {
        let response = try await client.getRecentRuns(query: .init(since: date, limit: limit))
        return try response.ok.body.json.map(AutomationRun.init)
    }

    public func activate(automation name: String) async throws {
        let response = try await client.activateAutomation(path: .init(name: name))
        _ = try response.ok
    }

    public func deactivate(automation name: String) async throws {
        let response = try await client.deactivateAutomation(path: .init(name: name))
        _ = try response.ok
    }

    public func stop(automation name: String) async throws {
        let response = try await client.stopAutomation(path: .init(name: name))
        _ = try response.ok
    }

    public func register(token: PushToken) async throws {
        let tokenType = Components.Schemas.PushDevice.TokenTypePayload.create(from: token.type)
        let body = Components.Schemas.PushDevice(deviceName: token.deviceName,
                                                 tokenString: token.tokenString,
                                                 tokenType: tokenType,
                                                 activityType: token.type.activityType)
        let response = try await client.registerPushDevice(.init(body: .json(body)))
        _ = try response.ok
    }

    /// The offenen Fenster as the server's Live Activity content state, in server order.
    public func getWindowContentState() async throws -> WindowContentState {
        let response = try await client.getWindowStates()
        let body = try response.ok.body.json
        let windows = try body.windowStates.map { state in
            WindowContentState.Window(id: state.id,
                                      name: state.name,
                                      room: state.room,
                                      opened: try Date(state.openedIsoTimeStamp, strategy: .iso8601),
                                      closeBy: try Date(state.closeByIsoTimeStamp, strategy: .iso8601),
                                      isOverdue: state.isOverdue)
        }
        return WindowContentState(windows: windows,
                                  openCount: body.openCount,
                                  overdueCount: body.overdueCount,
                                  outdoorTemperature: body.outdoorTemperature,
                                  staleDate: try body.staleDateIsoTimeStamp.map { try Date($0, strategy: .iso8601) })
    }

    public func getActions(limit: Int? = nil, runId: UUID? = nil) async throws -> [ActionLogItem] {
        let response = try await client.getActions(query: .init(limit: limit, runId: runId?.uuidString))
        return try response.ok.body.json.compactMap { item -> ActionLogItem? in
            guard let id = UUID(uuidString: item.id),
                  let characteristic = CharacteristicsType(rawValue: item.entityId.characteristicType) else {
                print("Failed to parse characteristic")
                assertionFailure("Failed to parse characteristic")
                return nil
            }
            let entityId = EntityId(placeId: item.entityId.placeId,
                                    name: item.entityId.name,
                                    characteristicsName: item.entityId.characteristicsName,
                                    characteristic: characteristic)
            return ActionLogItem(id: id,
                                 timestamp: item.timestamp,
                                 entityId: entityId,
                                 actionName: item.actionName,
                                 detailDescription: item.detailDescription,
                                 hasCacheHit: item.hasCacheHit,
                                 runId: item.runId.flatMap(UUID.init(uuidString:)),
                                 status: item.status.flatMap { ActionLogItem.Status(rawValue: $0.rawValue) },
                                 reason: item.reason.flatMap { HeatingWriteReason(rawValue: $0.rawValue) },
                                 planTargetInC: item.planTargetInC)
        }
    }

    public func clearActions() async throws {
        let response = try await client.clearActions()
        _ = try response.ok
    }

    public func getEntityIdsWithHistory() async throws -> [EntityInfo] {
        let response = try await client.getEntitiesWithHistory()
        return try response.ok.body.json.compactMap { entity -> EntityInfo? in
            guard let characteristic = CharacteristicsType(rawValue: entity.entityId.characteristicType) else {
                print("Failed to parse characteristic type: \(entity.entityId.characteristicType)")
                assertionFailure("Failed to parse characteristic type")
                return nil
            }
            let characteristicsName = entity.entityId.characteristicsName?.isEmpty == false ? entity.entityId.characteristicsName : nil
            let entityId = EntityId(placeId: entity.entityId.placeId,
                                   name: entity.entityId.name,
                                   characteristicsName: characteristicsName,
                                   characteristic: characteristic)
            return EntityInfo(entityId: entityId)
        }
    }

    public func getEntityHistory(
        entityId: EntityId,
        startDate: Date? = nil,
        endDate: Date? = nil,
        cursor: Date? = nil,
        limit: Int = 100,
        includePrevious: Bool = false
    ) async throws -> EntityHistoryResponse {
        let query = Operations.GetEntityHistory.Input.Query(
            placeId: entityId.placeId,
            name: entityId.name,
            characteristicsName: entityId.characteristicsName,
            characteristicType: entityId.characteristicType.rawValue,
            startDate: startDate,
            endDate: endDate,
            cursor: cursor,
            limit: limit,
            includePrevious: includePrevious
        )

        let response = try await client.getEntityHistory(query: query)
        let historyResponse = try response.ok.body.json

        return EntityHistoryResponse(
            items: historyResponse.items.map(EntityHistoryItem.init),
            nextCursor: historyResponse.nextCursor
        )
    }

    /// History of every entity in `placeId`, newest first; entities of unknown characteristic types are skipped.
    public func getRoomHistory(placeId: String, startDate: Date? = nil, endDate: Date? = nil, includePrevious: Bool = false) async throws -> [EntityHistory] {
        let response = try await client.getRoomHistory(query: .init(placeId: placeId,
                                                                    startDate: startDate,
                                                                    endDate: endDate,
                                                                    includePrevious: includePrevious))
        return try response.ok.body.json.compactMap { history in
            guard let entityId = EntityId(history.entityId) else { return nil }
            return EntityHistory(entityId: entityId, items: history.items.map(EntityHistoryItem.init))
        }
    }

    /// The rooms of the heating overview: actual, plan target and source of the actual value per room.
    public func getHeatingOverview() async throws -> HeatingOverview {
        let response = try await client.getHeatingOverview()
        let body = try response.ok.body.json
        return try HeatingOverview(rooms: body.rooms.map {
            try HeatingOverviewRoom(placeId: $0.placeId, name: $0.name, shortName: $0.shortName, ist: $0.ist, sollPlan: $0.sollPlan, delta: $0.delta,
                                istSource: HeatingIstSource($0.istSource), followsFireplace: $0.followsFireplace)
        }, heatmap: body.heatmap.map {
            HeatingHeatmapCell(placeId: $0.placeId, day: $0.day, segment: $0.segment, delta: $0.delta)
        })
    }

    /// The state of the fireplace switch (glossary: fireplace mode).
    public func getFireplace() async throws -> FireplaceState {
        FireplaceState(try await client.getFireplace().ok.body.json)
    }

    /// Switches the fireplace on or off; answers the state it will have.
    public func setFireplace(isOn: Bool) async throws -> FireplaceState {
        FireplaceState(try await client.setFireplace(body: .json(.init(isOn: isOn))).ok.body.json)
    }

    /// The time grid of a heating room (glossary: actual, plan target, Δ). Throws when the server answers
    /// 400 (unknown range) or 404 (no heating automation for the room).
    public func getHeatingRoom(placeId: String, range: HeatingRange) async throws -> HeatingRoomDetail {
        let response = try await client.getHeatingRoom(path: .init(placeId: placeId), query: .init(range: range.rawValue))
        let body = try response.ok.body.json
        guard let detailRange = HeatingRange(rawValue: body.range) else {
            throw InvalidResponseError(reason: "Unknown heating range \(body.range)")
        }
        let source = try HeatingIstSource(body.istSource)
        return HeatingRoomDetail(placeId: body.placeId,
                                 name: body.name,
                                 range: detailRange,
                                 istSource: source,
                                 radiators: body.radiators,
                                 samples: body.samples.map { HeatingSample(date: $0.date, ist: $0.ist, sollPlan: $0.sollPlan, valves: $0.valves) },
                                 lastIst: body.lastIst,
                                 events: (body.events ?? []).compactMap { event in
                                     guard let source = HeatingEventSource(rawValue: event.source) else {
                                         // A source this app does not know is a newer server or a bug: never drop it silently.
                                         Self.logger.warning("Dropped a heating event of an unknown source", metadata: ["source": "\(event.source)", "placeId": "\(body.placeId)"])
                                         return nil
                                     }
                                     return HeatingEvent(source: source, title: event.title, reason: event.reason, start: event.start, end: event.end, pin: event.pin)
                                 })
    }
}

extension FireplaceState {
    /// Takes the end the server named, so an app of another version shows when this server ends the fireplace.
    init(_ body: Components.Schemas.Fireplace) {
        self.init(isOn: body.isOn, since: body.since, endsAt: body.endsAt)
    }
}

extension HeatingIstSource {
    /// Throws when the server names a room sensor without its name: that is a server bug, not an empty name.
    init(_ source: Components.Schemas.HeatingIstSource) throws {
        switch source.kind {
        case .roomSensor:
            guard let name = source.names.first else {
                throw InvalidResponseError(reason: "A room sensor without a name")
            }
            self = .roomSensor(name)
        case .thermostats:
            self = .thermostats(source.names)
        }
    }
}

extension Components.Schemas.PushDevice.TokenTypePayload {
    static func create(from type: PushToken.TokenType) -> Self {
        switch type {
        case .pushNotification:
            return .pushNotification
        case .liveActivityStart:
            return .liveActivityStart
        case .liveActivityUpdate:
            return .liveActivityUpdate
        }
    }
}

struct InvalidResponseError: Error {
    let reason: String
}

extension EntityId {
    /// `nil` for a characteristic type this client does not know yet.
    init?(_ entityId: Components.Schemas.EntityId) {
        guard let characteristic = CharacteristicsType(rawValue: entityId.characteristicType) else { return nil }
        let characteristicsName = entityId.characteristicsName?.isEmpty == false ? entityId.characteristicsName : nil
        self.init(placeId: entityId.placeId, name: entityId.name, characteristicsName: characteristicsName, characteristic: characteristic)
    }
}

extension AutomationRun {
    init(_ run: Components.Schemas.AutomationRun) throws {
        guard let id = UUID(uuidString: run.id),
              let kind = AutomationTrigger.Kind(rawValue: run.trigger.kind.rawValue),
              let outcome = Outcome(rawValue: run.outcome.rawValue) else {
            throw InvalidResponseError(reason: "Invalid automation run \(run.id)")
        }
        self.init(id: id,
                  automationName: run.automationName,
                  startedAt: run.startedAt,
                  endedAt: run.endedAt,
                  trigger: AutomationTrigger(kind: kind, entityId: run.trigger.entityId.flatMap(EntityId.init), summary: run.trigger.summary),
                  outcome: outcome,
                  errorDescription: run.errorDescription)
    }
}

extension EntityHistoryItem {
    init(_ item: Components.Schemas.EntityHistoryItem) {
        self.init(timestamp: item.timestamp,
                  origin: item.origin,
                  lastReport: item.lastReport,
                  valueKind: item.valueKind,
                  value: item.value.flatMap(Value.init))
    }
}

extension Value {
    init?(_ payload: Components.Schemas.EntityHistoryItem.ValuePayload) {
        switch payload {
        case .case1(let bool): self = .bool(bool)
        case .case2(let number): self = .number(number)
        case .case3(let text): self = .text(text)
        }
    }
}

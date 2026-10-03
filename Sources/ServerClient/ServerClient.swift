//
//  ServerClient.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 26.02.25.
//

import Foundation
import HAModels
import OpenAPIURLSession

public struct ServerClient {
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

    public func getWindowStates() async throws -> [WindowContentState.WindowState] {
        let response = try await client.getWindowStates()
        return try response.ok.body.json.windowStates
            .map { state in
                let opened = try Date(state.openedIsoTimeStamp, strategy: .iso8601)
                return WindowContentState.WindowState(name: state.name,
                                                      opened: opened,
                                                      maxOpenDuration: state.maxOpenDuration)
            }
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
                                 status: item.status.flatMap { ActionLogItem.Status(rawValue: $0.rawValue) })
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
                  motionDetected: item.motionDetected,
                  illuminanceInLux: item.illuminanceInLux,
                  isDeviceOn: item.isDeviceOn,
                  brightness: item.brightness,
                  colorTemperature: item.colorTemperature,
                  colorRed: item.colorRed,
                  colorGreen: item.colorGreen,
                  colorBlue: item.colorBlue,
                  isContactOpen: item.isContactOpen,
                  isDoorLocked: item.isDoorLocked,
                  stateOfCharge: item.stateOfCharge,
                  isHeaterActive: item.isHeaterActive,
                  temperatureInC: item.temperatureInC,
                  relativeHumidity: item.relativeHumidity,
                  carbonDioxideSensorId: item.carbonDioxideSensorId,
                  pmDensity: item.pmDensity,
                  airQuality: item.airQuality,
                  valveOpen: item.valveOpen)
    }
}

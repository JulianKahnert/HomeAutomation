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

        self.client = Client(
            serverURL: url,
            transport: URLSessionTransport(configuration: .init(session: session))
        )
    }

    public func getAutomations() async throws -> [AutomationInfo] {
        let response = try await client.getAutomations()
        return try response.ok.body.json
            .map { automation in
                AutomationInfo(name: automation.name,
                               isActive: automation.isActive,
                               isRunning: automation.isRunning)
            }
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

    public func getActions(limit: Int? = nil) async throws -> [ActionLogItem] {
        let response = try await client.getActions(query: .init(limit: limit))
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
                                 hasCacheHit: item.hasCacheHit)
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
        limit: Int = 100
    ) async throws -> EntityHistoryResponse {
        let query = Operations.GetEntityHistory.Input.Query(
            placeId: entityId.placeId,
            name: entityId.name,
            characteristicsName: entityId.characteristicsName,
            characteristicType: entityId.characteristicType.rawValue,
            startDate: startDate,
            endDate: endDate,
            cursor: cursor,
            limit: limit
        )

        let response = try await client.getEntityHistory(query: query)
        let historyResponse = try response.ok.body.json

        let items = historyResponse.items.compactMap { item -> EntityHistoryItem? in
            EntityHistoryItem(
                timestamp: item.timestamp,
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
                valveOpen: item.valveOpen
            )
        }

        return EntityHistoryResponse(
            items: items,
            nextCursor: historyResponse.nextCursor
        )
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

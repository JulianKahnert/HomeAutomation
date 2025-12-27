//
//  OpenAPIController.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 14.02.25.
//

import Dependencies
import Fluent
import HAModels
import OpenAPIRuntime
import Vapor

struct OpenAPIController: APIProtocol {
    @Dependency(\.request) var request

    // MARK: - /config/automations

    func getAutomations(_ input: Operations.GetAutomations.Input) async throws -> Operations.GetAutomations.Output {
        let automationNames = await request.application.automationService.getActiveAutomationNames()
        let automations = await request.application.homeAutomationConfigService.automations
            .map { tmp in
                Components.Schemas.Automation(name: tmp.name,
                                              isActive: tmp.isActive,
                                              isRunning: automationNames.contains(tmp.name))
            }
        return .ok(.init(body: .json(automations)))
    }

    func activateAutomation(_ input: Operations.ActivateAutomation.Input) async throws -> Operations.ActivateAutomation.Output {
        guard let name = request.parameters.get("name"),
              !name.isEmpty else {
            throw Abort(.notFound, reason: "Automation name not provided")
        }

        await request.application.homeAutomationConfigService.setAutomationActive(with: name, to: true)
        return .ok
    }

    func deactivateAutomation(_ input: Operations.DeactivateAutomation.Input) async throws -> Operations.DeactivateAutomation.Output {
        guard let name = request.parameters.get("name"),
              !name.isEmpty else {
            throw Abort(.notFound, reason: "Automation name not provided")
        }

        await request.application.homeAutomationConfigService.setAutomationActive(with: name, to: false)
        return .ok
    }

    func stopAutomation(_ input: Operations.StopAutomation.Input) async throws -> Operations.StopAutomation.Output {
        guard let name = request.parameters.get("name"),
              !name.isEmpty else {
            throw Abort(.notFound, reason: "Automation name not provided")
        }

        await request.application.automationService.stopAutomation(with: name)
        return .ok
    }

    // MARK: - /pushdevices

    func registerPushDevice(_ input: Operations.RegisterPushDevice.Input) async throws -> Operations.RegisterPushDevice.Output {
       guard case let .json(token) = input.body else {
            throw Abort(.badRequest, reason: "Invalid JSON body")
        }
        request.logger.info("Adding/updating push device token: \(token.tokenType.rawValue)")

        switch token.tokenType {
        case .pushNotification, .liveActivityStart:
            assert(token.activityType == nil, "For pushNotification and liveActivityStart, activityType should be nil")

            // first delete all previous token
            try await DeviceToken
                .query(on: request.db)
                .filter(\.$deviceName == token.deviceName)
                .filter(\.$tokenType == token.tokenType.rawValue)
                .delete()

            // add the new token
            let newPushDevice = DeviceToken(deviceName: token.deviceName,
                                            tokenString: token.tokenString,
                                            tokenType: token.tokenType.rawValue,
                                            activityType: token.activityType) // for pushNotification & liveActivityStart - this should always be nil
            try await newPushDevice.save(on: request.db)
            return .ok

        case .liveActivityUpdate:
            guard let activityType = token.activityType else {
                request.logger.critical("Token of type liveActivityUpdate must contain activityType")
                return .internalServerError
            }

            // delete other tokens with that activity type
            try await DeviceToken
                .query(on: request.db)
                .filter(\.$deviceName == token.deviceName)
                .filter(\.$tokenString != token.tokenString)
                .filter(\.$tokenType == token.tokenType.rawValue)
                .filter(\.$activityType == activityType)
                .delete()

            // insert the new token, if needed
            let numberOfPushDevices = try await DeviceToken
                .query(on: request.db)
                .filter(\.$deviceName == token.deviceName)
                .filter(\.$tokenString == token.tokenString)
                .filter(\.$tokenType == token.tokenType.rawValue)
                .filter(\.$activityType == activityType)
                .count()
            if numberOfPushDevices == 0 {
                let newPushDevice = DeviceToken(deviceName: token.deviceName,
                                                tokenString: token.tokenString,
                                                tokenType: token.tokenType.rawValue,
                                                activityType: activityType)

                try await newPushDevice.save(on: request.db)
            }
            return .ok
        }
    }

    // MARK: - /windowopenstates
    func getWindowStates(_ input: Operations.GetWindowStates.Input) async throws -> Operations.GetWindowStates.Output {
        let states: [Components.Schemas.WindowState] = await request.application.homeManager.getWindowStates()
            .map { state in
                Components.Schemas.WindowState(name: state.name,
                                               openedIsoTimeStamp: state.opened.ISO8601Format(),
                                               maxOpenDuration: state.maxOpenDuration)
            }

        return .ok(.init(body: .json(.init(windowStates: states))))
    }

    // MARK: - /actions

    func getActions(_ input: Operations.GetActions.Input) async throws -> Operations.GetActions.Output {
        let limit = input.query.limit

        let actionItems = await request.application.homeManager.getActionLog(limit: limit)

        // Map to OpenAPI schema types
        let schemaItems = actionItems.compactMap { item -> Components.Schemas.ActionLogItem? in
            let entityId = Components.Schemas.EntityId(placeId: item.entityId.placeId,
                                                       name: item.entityId.name,
                                                       characteristicsName: item.entityId.characteristicsName ?? "",
                                                       characteristicType: item.entityId.characteristicType.rawValue)

            return Components.Schemas.ActionLogItem(id: item.id.uuidString,
                                                    timestamp: item.timestamp,
                                                    entityId: entityId,
                                                    actionName: item.actionName,
                                                    detailDescription: item.detailDescription,
                                                    hasCacheHit: item.hasCacheHit)
        }

        return .ok(.init(body: .json(schemaItems)))
    }

    func clearActions(_ input: Operations.ClearActions.Input) async throws -> Operations.ClearActions.Output {
        await request.application.homeManager.clearActionLog()
        return .ok
    }

    // MARK: - /entities

    func getEntitiesWithHistory(_ input: Operations.GetEntitiesWithHistory.Input) async throws -> Operations.GetEntitiesWithHistory.Output {
        // Get all unique entity IDs that have history
        let entityIds = try await request.application.entityStorageDbRepository.getAllEntityIds()

        // Map EntityIds to EntityInfo
        let entityInfos = entityIds.map { entityId in
            Components.Schemas.EntityInfo(
                id: "\(entityId.placeId)_\(entityId.name)_\(entityId.characteristicType.rawValue)",
                entityId: Components.Schemas.EntityId(
                    placeId: entityId.placeId,
                    name: entityId.name,
                    characteristicsName: entityId.characteristicsName ?? "",
                    characteristicType: entityId.characteristicType.rawValue
                )
            )
        }

        return .ok(.init(body: .json(entityInfos)))
    }

    // MARK: - /entities/history

    func getEntityHistory(_ input: Operations.GetEntityHistory.Input) async throws -> Operations.GetEntityHistory.Output {
        // Extract and validate required query parameters
        guard let characteristicType = CharacteristicsType(rawValue: input.query.characteristicType) else {
            throw Abort(.badRequest, reason: "Invalid characteristic type: \(input.query.characteristicType)")
        }

        let entityId = EntityId(
            placeId: input.query.placeId,
            name: input.query.name,
            characteristicsName: input.query.characteristicsName,
            characteristic: characteristicType
        )

        // Extract optional date parameters (already parsed by OpenAPI)
        let startDate = input.query.startDate
        let endDate = input.query.endDate
        let cursor = input.query.cursor
        let limit = input.query.limit ?? 100

        // Query history from repository
        let historyItems = try await request.application.entityStorageDbRepository.getHistory(
            for: entityId,
            startDate: startDate,
            endDate: endDate,
            cursor: cursor,
            limit: limit
        )

        // Map to OpenAPI schema types
        let schemaItems = historyItems.map { item in
            Components.Schemas.EntityHistoryItem(
                timestamp: item.timestamp,
                motionDetected: item.motionDetected,
                illuminanceInLux: item.illuminance?.value,
                isDeviceOn: item.isDeviceOn,
                brightness: item.brightness,
                colorTemperature: item.colorTemperature,
                colorRed: item.color?.red,
                colorGreen: item.color?.green,
                colorBlue: item.color?.blue,
                isContactOpen: item.isContactOpen,
                isDoorLocked: item.isDoorLocked,
                stateOfCharge: item.stateOfCharge,
                isHeaterActive: item.isHeaterActive,
                temperatureInC: item.temperatureInC?.value,
                relativeHumidity: item.relativeHumidity,
                carbonDioxideSensorId: item.carbonDioxideSensorId,
                pmDensity: item.pmDensity,
                airQuality: item.airQuality,
                valveOpen: item.valveOpen
            )
        }

        // Calculate next cursor (timestamp of last item, or nil if no more data)
        let nextCursor = schemaItems.last?.timestamp

        let response = Components.Schemas.EntityHistoryResponse(
            items: schemaItems,
            nextCursor: nextCursor
        )

        return .ok(.init(body: .json(response)))
    }

}

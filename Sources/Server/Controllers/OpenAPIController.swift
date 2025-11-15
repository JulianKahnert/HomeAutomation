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

        let actionItems = await ActionLogger.shared.getActions(limit: limit)

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
        await ActionLogger.shared.clear()
        return .ok
    }

}

//
//  ConfigController.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 14.02.25.
//

import Dependencies
import Fluent
import Vapor

struct ConfigController: APIProtocol {
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
       guard case let .json(content) = input.body else {
            throw Abort(.badRequest, reason: "Invalid JSON body")
        }
        
        switch content.tokenType {
        case .pushNotification, .liveActivityStart:
            let numberOfPushDevices = try await DeviceToken
                .query(on: request.db)
                .filter(\.$deviceName == content.deviceName)
                .filter(\.$tokenString == content.tokenString)
                .filter(\.$tokenType == content.tokenType.rawValue)
                .count()
            if numberOfPushDevices == 0 {
                let newPushDevice = DeviceToken(id: nil,
                                                deviceName: content.deviceName,
                                                tokenString: content.tokenString,
                                                tokenType: content.tokenType.rawValue,
                                                activityType: content.activityType) // for pushNotification & liveActivityStart - this should always be nil
                try await newPushDevice.save(on: request.db)
            }
            return .ok
        
        case .liveActivityUpdate:
            guard let activityType = content.activityType else {
                request.logger.critical("Token of type liveActivityUpdate must contain activityType")
                return .internalServerError
            }
            
            // delete other tokens with that activity type
            try await DeviceToken
                .query(on: request.db)
                .filter(\.$deviceName == content.deviceName)
                .filter(\.$tokenString != content.tokenString)
                .filter(\.$tokenType == content.tokenType.rawValue)
                .filter(\.$activityType == activityType)
                .delete()
            
            // insert the new token, if needed
            let numberOfPushDevices = try await DeviceToken
                .query(on: request.db)
                .filter(\.$deviceName == content.deviceName)
                .filter(\.$tokenString == content.tokenString)
                .filter(\.$tokenType == content.tokenType.rawValue)
                .filter(\.$activityType == activityType)
                .count()
            if numberOfPushDevices == 0 {
                let newPushDevice = DeviceToken(id: nil,
                                                deviceName: content.deviceName,
                                                tokenString: content.tokenString,
                                                tokenType: content.tokenType.rawValue,
                                                activityType: content.activityType) // this should always be nil
                try await newPushDevice.save(on: request.db)
            }
            return .ok
        }
    }
}

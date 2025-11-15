//
//  FlowKitClient.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 26.02.25.
//

import Foundation
import HAModels
import OpenAPIURLSession

struct FlowKitClient {
    static let userDefaultsKey = "AutomationClientUrl"

    private let client: Client

    init(url: URL) {
        self.client = Client(
            serverURL: url,
            transport: URLSessionTransport()
        )
    }

    func getAutomations() async throws -> [Components.Schemas.Automation] {
        let response = try await client.getAutomations()
        return try response.ok.body.json
    }

    func activate(automation name: String) async throws {
        let response = try await client.activateAutomation(path: .init(name: name))
        _ = try response.ok
    }

    func deactivate(automation name: String) async throws {
        let response = try await client.deactivateAutomation(path: .init(name: name))
        _ = try response.ok
    }

    func stop(automation name: String) async throws {
        let response = try await client.stopAutomation(path: .init(name: name))
        _ = try response.ok
    }

    func register(deviceName: String, tokenString: String, tokenType: Components.Schemas.PushDevice.TokenTypePayload, activityType: String?) async throws {
        let body: Components.Schemas.PushDevice = .init(deviceName: deviceName, tokenString: tokenString, tokenType: tokenType, activityType: activityType)
        let response = try await client.registerPushDevice(.init(body: .json(body)))
        _ = try response.ok
    }

    func getWindowStates() async throws -> [WindowContentState.WindowState] {
        let response = try await client.getWindowStates()
        return try response.ok.body.json.windowStates
            .map { state in
                let opened = try Date(state.openedIsoTimeStamp, strategy: .iso8601)
                return WindowContentState.WindowState(name: state.name,
                                                      opened: opened,
                                                      maxOpenDuration: state.maxOpenDuration)
            }
    }

    func getActions(limit: Int? = nil) async throws -> [ActionLogItem] {
        let response = try await client.getActions(query: .init(limit: limit))
        return try response.ok.body.json
    }

    func clearActions() async throws {
        let response = try await client.clearActions()
        _ = try response.ok
    }
}

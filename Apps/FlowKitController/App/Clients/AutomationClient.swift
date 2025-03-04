//
//  AutomationClient.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 26.02.25.
//

import Foundation
import OpenAPIURLSession

struct AutomationClient {
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
}

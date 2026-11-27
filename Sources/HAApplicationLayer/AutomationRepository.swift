//
//  AutomationRepository.swift
//  HomeAutomationKit
//

import HAModels

/// Stores the deployed automations, including their active state.
public protocol AutomationRepository: Sendable {
    func save(_ automations: [any Automatable]) async throws
}

/// Keeps the last saved automations in memory; for tests and previews.
public actor InMemoryAutomationRepository: AutomationRepository {
    public private(set) var saved: [any Automatable] = []

    public init() {}

    public func save(_ automations: [any Automatable]) async throws {
        saved = automations
    }
}

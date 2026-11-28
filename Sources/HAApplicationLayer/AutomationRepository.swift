//
//  AutomationRepository.swift
//  HomeAutomationKit
//

import HAModels

/// Stores the deployed automations, including their active state.
public protocol AutomationRepository: Sendable {
    /// - Parameter location: The location of a deployed config, stored along with the automations; `nil` keeps the one stored.
    func save(_ automations: [any Automatable], location: Location?) async throws
}

/// Keeps the last saved automations in memory; for tests and previews.
public actor InMemoryAutomationRepository: AutomationRepository {
    public private(set) var saved: [any Automatable] = []

    public init() {}

    public func save(_ automations: [any Automatable], location: Location?) async throws {
        saved = automations
    }
}

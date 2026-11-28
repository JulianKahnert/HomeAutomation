//
//  AutomationServiceFixture.swift
//  HomeAutomationServer
//

import Foundation
import HAApplicationLayer
import HAModels
@testable import Server

/// Runs are not recorded; the tests of the routes only read the deployed automations.
actor NoRuns: AutomationRunRepository {
    func add(_ run: AutomationRun) async throws {}
    func finish(_ id: UUID, outcome: AutomationRun.Outcome, endedAt: Date, errorDescription: String?) async throws {}
    func runs(for automationName: String, startDate: Date?, endDate: Date?, limit: Int) async throws -> [AutomationRun] { [] }
    func latestRuns(since date: Date, limit: Int) async throws -> [AutomationRun] { [] }
    func latestRunPerAutomation() async throws -> [String: AutomationRun] { [:] }
    func markRunningAsInterrupted() async throws {}
}

func makeAutomationService(automations: [any Automatable],
                           repository: any AutomationRepository = InMemoryAutomationRepository()) async throws -> AutomationService {
    let homeManager = await HomeManager(getAdapter: { nil },
                                        storageRepo: MemoryStorage(),
                                        notificationSender: SilentSender(),
                                        location: Location(latitude: 52.52, longitude: 13.405))
    return try AutomationService(using: homeManager, runs: NoRuns(), automations: automations, repository: repository)
}

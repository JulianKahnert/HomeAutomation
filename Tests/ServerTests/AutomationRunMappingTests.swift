//
//  AutomationRunMappingTests.swift
//  HomeAutomation
//

import Foundation
import HAModels
@testable import Server
import Testing

/// The repository queries need MySQL; these cover the row and API mappings without a database.
struct AutomationRunMappingTests {
    private let entityId = EntityId(placeId: "Hallway", name: "Eve Motion", characteristicsName: "Motion", characteristic: .motionSensor)

    @Test(arguments: AutomationRun.Outcome.allCases)
    func dbItemRoundTripKeepsAllFields(outcome: AutomationRun.Outcome) throws {
        let run = AutomationRun(automationName: "Night light",
                                startedAt: Date(timeIntervalSince1970: 1_000),
                                endedAt: Date(timeIntervalSince1970: 1_060),
                                trigger: AutomationTrigger(kind: .entityChange, entityId: entityId, summary: "Motion · Eve Motion (Hallway)"),
                                outcome: outcome,
                                errorDescription: "boom")

        #expect(try AutomationRunDbItem(run).toRun() == run)
    }

    @Test(arguments: AutomationTrigger.Kind.allCases)
    func dbItemRoundTripWithoutEntity(kind: AutomationTrigger.Kind) throws {
        let run = AutomationRun(automationName: "a",
                                startedAt: Date(timeIntervalSince1970: 0),
                                trigger: AutomationTrigger(kind: kind, entityId: nil, summary: "s"),
                                outcome: .running)

        #expect(try AutomationRunDbItem(run).toRun() == run)
    }

    @Test(arguments: AutomationRun.Outcome.allCases)
    func apiSchemaCarriesEveryOutcome(outcome: AutomationRun.Outcome) {
        let run = AutomationRun(automationName: "a", startedAt: Date(), trigger: AutomationTrigger(kind: .sunset, entityId: nil, summary: "Sunset"), outcome: outcome)

        let schema = Components.Schemas.AutomationRun(run)

        #expect(schema.outcome.rawValue == outcome.rawValue)
        #expect(schema.trigger.kind.rawValue == "sunset")
    }
}

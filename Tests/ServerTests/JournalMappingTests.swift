//
//  JournalMappingTests.swift
//  HomeAutomation
//

import Foundation
import HAModels
@testable import Server
import Testing

/// The repository queries need MySQL; these cover the row and API mappings without a database.
struct JournalMappingTests {
    private let entityId = EntityId(placeId: "Hallway", name: "Eve Motion", characteristicsName: "Motion", characteristic: .motionSensor)

    @Test(arguments: AutomationRun.Outcome.allCases)
    func dbItemRoundTripKeepsAllFields(outcome: AutomationRun.Outcome) throws {
        let run = AutomationRun(automationName: "Night light",
                                startedAt: Date(timeIntervalSince1970: 1_000),
                                endedAt: Date(timeIntervalSince1970: 1_060),
                                trigger: AutomationTrigger(kind: .entityChange, entityId: entityId, summary: "Motion · Eve Motion (Hallway)"),
                                outcome: outcome,
                                errorDescription: "boom")

        #expect(try JournalDbItem(run).toRun() == run)
    }

    @Test(arguments: AutomationTrigger.Kind.allCases)
    func dbItemRoundTripWithoutEntity(kind: AutomationTrigger.Kind) throws {
        let run = AutomationRun(automationName: "a",
                                startedAt: Date(timeIntervalSince1970: 0),
                                trigger: AutomationTrigger(kind: kind, entityId: nil, summary: "s"),
                                outcome: .running)

        #expect(try JournalDbItem(run).toRun() == run)
    }

    @Test(arguments: ActionLogItem.Status.allCases)
    func commandRoundTripKeepsAllFields(status: ActionLogItem.Status) throws {
        let runId = UUID()
        let command = ActionLogItem(timestamp: Date(timeIntervalSince1970: 500),
                                    action: .setTargetTemperature(entityId, celsius: 21),
                                    status: status,
                                    runId: runId,
                                    reason: .plan,
                                    planTargetInC: 21)

        let row = JournalDbItem(command)

        #expect(row.kind == "command")
        #expect(row.runId == runId)
        #expect(try row.toCommand() == command)
    }

    @Test
    func commandWithoutRunOrReasonRoundTrips() throws {
        let command = ActionLogItem(timestamp: Date(timeIntervalSince1970: 1), action: .turnOn(entityId))

        #expect(try JournalDbItem(command).toCommand() == command)
    }

    @Test
    func pushRoundTripKeepsAllFields() throws {
        let push = JournalPush(timestamp: Date(timeIntervalSince1970: 7), runId: UUID(), title: "Fenster", message: "offen", pushId: "window-1")

        let row = JournalDbItem(push)

        #expect(row.kind == "push")
        #expect(try row.toPush() == push)
    }

    @Test
    func runRowCarriesItsOwnIdAsRunId() {
        let run = AutomationRun(automationName: "a", startedAt: Date(), trigger: AutomationTrigger(kind: .sunset, entityId: nil, summary: "s"), outcome: .running)

        #expect(JournalDbItem(run).runId == run.id)
    }

    @Test
    func rowOfAnotherKindIsNotRead() {
        let push = JournalDbItem(JournalPush(runId: nil, title: "t", message: "m", pushId: "p"))

        #expect(throws: DecodingError.self) { try push.toRun() }
        #expect(throws: DecodingError.self) { try push.toCommand() }
    }

    @Test(arguments: AutomationRun.Outcome.allCases)
    func apiSchemaCarriesEveryOutcome(outcome: AutomationRun.Outcome) {
        let run = AutomationRun(automationName: "a", startedAt: Date(), trigger: AutomationTrigger(kind: .sunset, entityId: nil, summary: "Sunset"), outcome: outcome)

        let schema = Components.Schemas.AutomationRun(run)

        #expect(schema.outcome.rawValue == outcome.rawValue)
        #expect(schema.trigger.kind.rawValue == "sunset")
    }
}

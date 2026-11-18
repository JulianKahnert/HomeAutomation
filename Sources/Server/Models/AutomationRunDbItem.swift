//
//  AutomationRunDbItem.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAModels

final class AutomationRunDbItem: Model, @unchecked Sendable {
    static let schema = "automationRuns"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "automationName")
    var automationName: String

    @Field(key: "startedAt")
    var startedAt: Date

    @OptionalField(key: "endedAt")
    var endedAt: Date?

    @Field(key: "triggerKind")
    var triggerKind: String

    @OptionalField(key: "triggerPlaceId")
    var triggerPlaceId: String?

    @OptionalField(key: "triggerName")
    var triggerName: String?

    @OptionalField(key: "triggerCharacteristicsName")
    var triggerCharacteristicsName: String?

    @OptionalField(key: "triggerCharacteristicType")
    var triggerCharacteristicType: String?

    @Field(key: "triggerSummary")
    var triggerSummary: String

    @Field(key: "outcome")
    var outcome: String

    @OptionalField(key: "errorDescription")
    var errorDescription: String?

    init() { }

    init(_ run: AutomationRun) {
        id = run.id
        automationName = run.automationName
        startedAt = run.startedAt
        endedAt = run.endedAt
        triggerKind = run.trigger.kind.rawValue
        triggerPlaceId = run.trigger.entityId?.placeId
        triggerName = run.trigger.entityId?.name
        triggerCharacteristicsName = run.trigger.entityId?.characteristicsName
        triggerCharacteristicType = run.trigger.entityId?.characteristicType.rawValue
        triggerSummary = run.trigger.summary
        outcome = run.outcome.rawValue
        errorDescription = run.errorDescription
    }

    func toRun() throws -> AutomationRun {
        guard let id,
              let kind = AutomationTrigger.Kind(rawValue: triggerKind),
              let outcome = AutomationRun.Outcome(rawValue: outcome) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid automation run row \(String(describing: id))"))
        }
        var entityId: EntityId?
        if let triggerPlaceId, let triggerName,
           let characteristic = triggerCharacteristicType.flatMap(CharacteristicsType.init(rawValue:)) {
            entityId = EntityId(placeId: triggerPlaceId, name: triggerName, characteristicsName: triggerCharacteristicsName, characteristic: characteristic)
        }
        return AutomationRun(id: id,
                             automationName: automationName,
                             startedAt: startedAt,
                             endedAt: endedAt,
                             trigger: AutomationTrigger(kind: kind, entityId: entityId, summary: triggerSummary),
                             outcome: outcome,
                             errorDescription: errorDescription)
    }
}

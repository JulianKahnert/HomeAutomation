//
//  JournalDbItem.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAModels

/// One row of the journal: a run, a command or a push, told apart by `kind`. A command and a push carry
/// the id of their run in `runId`; the row of a run carries its own id there, so `runId = ?` selects a
/// run with all its commands and pushes. Columns that do not fit a kind stay `NULL`.
///
/// | column | run | command | push |
/// |---|---|---|---|
/// | `timestamp` | start | time of the command | time of the push |
/// | `title` | automation name | action name | push title |
/// | `detail` | trigger summary | action description | push message |
/// | `entity*` | trigger entity | commanded entity | |
/// | `triggerKind`, `outcome`, `endedAt`, `errorDescription` | yes | | |
/// | `status`, `reason`, `commandValue` | | yes | |
/// | `pushId` | | | yes |
final class JournalDbItem: Model, @unchecked Sendable {
    static let schema = "journal"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "kind")
    var kind: String

    @Field(key: "timestamp")
    var timestamp: Date

    @OptionalField(key: "runId")
    var runId: UUID?

    @Field(key: "title")
    var title: String

    @Field(key: "detail")
    var detail: String

    @OptionalField(key: "entityPlaceId")
    var entityPlaceId: String?

    @OptionalField(key: "entityName")
    var entityName: String?

    @OptionalField(key: "entityCharacteristicsName")
    var entityCharacteristicsName: String?

    @OptionalField(key: "entityCharacteristicType")
    var entityCharacteristicType: String?

    @OptionalField(key: "triggerKind")
    var triggerKind: String?

    @OptionalField(key: "outcome")
    var outcome: String?

    @OptionalField(key: "endedAt")
    var endedAt: Date?

    @OptionalField(key: "errorDescription")
    var errorDescription: String?

    @OptionalField(key: "status")
    var status: String?

    @OptionalField(key: "reason")
    var reason: String?

    @OptionalField(key: "commandValue")
    var commandValue: Double?

    @OptionalField(key: "pushId")
    var pushId: String?

    /// The widths of the `title` and `detail` columns; a longer text is cut, because a too long value would fail the insert.
    static let titleLimit = 255
    static let detailLimit = 1000

    init() { }

    init(_ run: AutomationRun) {
        id = run.id
        kind = JournalKind.run.rawValue
        timestamp = run.startedAt
        runId = run.id
        title = run.automationName.fitted(toScalars: Self.titleLimit)
        detail = run.trigger.summary.fitted(toScalars: Self.detailLimit)
        setEntity(run.trigger.entityId)
        triggerKind = run.trigger.kind.rawValue
        outcome = run.outcome.rawValue
        endedAt = run.endedAt
        errorDescription = run.errorDescription
    }

    init(_ command: ActionLogItem) {
        id = command.id
        kind = JournalKind.command.rawValue
        timestamp = command.timestamp
        runId = command.runId
        title = command.actionName.fitted(toScalars: Self.titleLimit)
        detail = command.detailDescription.fitted(toScalars: Self.detailLimit)
        setEntity(command.entityId)
        status = command.status.rawValue
        reason = command.reason?.rawValue
        commandValue = command.value
    }

    init(_ push: JournalPush) {
        id = push.id
        kind = JournalKind.push.rawValue
        timestamp = push.timestamp
        runId = push.runId
        title = push.title.fitted(toScalars: Self.titleLimit)
        detail = push.message.fitted(toScalars: Self.detailLimit)
        pushId = push.pushId
    }

    private func setEntity(_ entityId: EntityId?) {
        entityPlaceId = entityId?.placeId
        entityName = entityId?.name
        entityCharacteristicsName = entityId?.characteristicsName
        entityCharacteristicType = entityId?.characteristicType.rawValue
    }

    private var entityId: EntityId? {
        guard let entityPlaceId, let entityName,
              let characteristic = entityCharacteristicType.flatMap(CharacteristicsType.init(rawValue:)) else { return nil }
        return EntityId(placeId: entityPlaceId, name: entityName, characteristicsName: entityCharacteristicsName, characteristic: characteristic)
    }

    private func corrupt() -> DecodingError {
        DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid journal row \(String(describing: id))"))
    }

    func toRun() throws -> AutomationRun {
        guard let id,
              kind == JournalKind.run.rawValue,
              let triggerKind, let kind = AutomationTrigger.Kind(rawValue: triggerKind),
              let outcome, let outcome = AutomationRun.Outcome(rawValue: outcome) else { throw corrupt() }
        return AutomationRun(id: id,
                             automationName: title,
                             startedAt: timestamp,
                             endedAt: endedAt,
                             trigger: AutomationTrigger(kind: kind, entityId: entityId, summary: detail),
                             outcome: outcome,
                             errorDescription: errorDescription)
    }

    func toCommand() throws -> ActionLogItem {
        guard let id, kind == JournalKind.command.rawValue, let entityId,
              let status = status.flatMap(ActionLogItem.Status.init(rawValue:)) else { throw corrupt() }
        return ActionLogItem(id: id,
                             timestamp: timestamp,
                             entityId: entityId,
                             actionName: title,
                             detailDescription: detail,
                             status: status,
                             runId: runId,
                             reason: reason.flatMap(HeatingWriteReason.init(rawValue:)),
                             value: commandValue)
    }

    func toPush() throws -> JournalPush {
        guard let id, kind == JournalKind.push.rawValue, let pushId else { throw corrupt() }
        return JournalPush(id: id, timestamp: timestamp, runId: runId, title: title, message: detail, pushId: pushId)
    }
}

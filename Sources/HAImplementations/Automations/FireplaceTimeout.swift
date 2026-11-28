//
//  FireplaceTimeout.swift
//  HAImplementations
//

import Foundation
import HAModels

/// Asks "Ist der Kamin noch an?" `Fireplace.maxDuration` after the fireplace was switched on, and ends it when
/// nobody answers (glossary: fireplace question, fireplace end).
///
/// - At the question it reports `Fireplace.questionId` overdue and starts the question Live Activity on every device.
/// - "Ja" (`POST /heating/fireplace/answer`) sets the next question `Fireplace.maxDuration` ahead; "Nein" switches
///   the fireplace off. Either change ends the Live Activity on every device, also on the devices nobody answered on.
/// - Without an answer it switches the fireplace off `Fireplace.answerTimeout` after asking, with the push
///   "Kamin aus", like the former fixed end.
///
/// All times count from what the server stored, so a server restart neither restarts nor skips them. Ending the
/// fireplace reports the entity off (origin `server`), which tells the rooms that follow it to return to their plan.
public struct FireplaceTimeout: Automatable {
    public var isActive = true
    public let name: String
    /// Every change runs to its end in order: a superseded run could cut the Live Activity send of the question
    /// by the change event that very question causes.
    public var lanePolicy: LanePolicy { .runEach }

    public init(_ name: String = "fireplace-timeout") {
        self.name = name
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        switch event {
        case .time(let date):
            let state = try await Fireplace.state(with: hm)
            guard state.isOn else { return false }
            let due = state.isAsking ? state.endsAt : state.asksAt
            return due.map { date >= $0 } ?? false
        case .change(let item):
            // An answer, the fireplace switched off, or the question just asked: execute decides what is left to do.
            return item.entityId == Fireplace.stateId || item.entityId == Fireplace.questionId
        case .sunrise, .sunset, .serverStarted, .configDeployed:
            return false
        }
    }

    public func execute(using hm: HomeManagable) async throws {
        try await execute(using: hm, on: AutomationRunContext.event, now: Date())
    }

    func execute(using hm: HomeManagable, on event: HomeEvent?, now: Date) async throws {
        let fireplace = try await current(Fireplace.stateId, using: hm)
        let question = try await current(Fireplace.questionId, using: hm)
        let state = Fireplace.state(of: fireplace, question: question)

        guard state.isOn else {
            // "Nein", the switch in the app or the end without answer: an open question closes for everyone.
            guard question?.deadline?.isOverdue == true else { return }
            _ = try await hm.report(Fireplace.questionId, value: .text(Deadline.none.text), origin: .server, ifCurrent: { $0?.deadline?.isOverdue == true })
            await endQuestion(using: hm)
            return
        }

        if state.isAsking {
            guard let endsAt = state.endsAt, now >= endsAt else { return }
            try await end(since: state.since, using: hm)
            return
        }

        // "Ja": the next question is set ahead, the open one closes for everyone.
        if case .change(let item)? = event, item.entityId == Fireplace.questionId, case .running? = item.deadline {
            await endQuestion(using: hm)
        }

        guard let asksAt = state.asksAt, let since = state.since, now >= asksAt else { return }
        try await ask(at: asksAt, since: since, read: question, using: hm)
    }

    /// Opens the question unless another writer (an answer "Ja") changed it since this run read it.
    private func ask(at asksAt: Date, since: Date, read question: EntityStorageItem?, using hm: HomeManagable) async throws {
        let asked = Deadline.overdue(since: asksAt)
        guard try await hm.report(Fireplace.questionId, value: .text(asked.text), origin: .server, ifCurrent: { item in
            item?.value == question?.value
        }) else { return }
        // The question was reported after the switch-on, so the state now reads it as open.
        let endsAt = asksAt.addingTimeInterval(Fireplace.answerTimeout)
        log.info("Asking whether the fireplace still burns", metadata: ["endsAt": "\(endsAt)"])
        let contentState = FireplaceContentState(since: since, endsAt: endsAt)
        let options = LiveActivityOptions(alert: .init(title: "Ist der Kamin noch an?", body: "Ohne Antwort schaltet der Server den Kamin-Modus aus."),
                                          staleDate: endsAt,
                                          priority: .high)
        await hm.deliver(.liveActivity(contentState: contentState, activityName: FireplaceContentState.activityTypeName, options: options))
    }

    /// Nobody answered: switches the fireplace off, decided where the state is set so an answer or a new start
    /// that came in since the trigger is not overruled.
    private func end(since: Date?, using hm: HomeManagable) async throws {
        guard try await hm.report(Fireplace.stateId, value: .bool(false), origin: .server, ifCurrent: { item in
            item?.isDeviceOn == true && item?.timestamp == since
        }) else { return }
        // The change of the switch closes the question and ends the Live Activity in the next run.
        await hm.deliver(.push(title: "Kamin aus",
                               message: "Niemand hat bestätigt, dass der Kamin noch an ist. Die Heizkörper folgen wieder dem Plan.",
                               id: Fireplace.notificationId))
    }

    /// The stored item, `nil` for an entity the server never held; any other read failure ends the run.
    private func current(_ entityId: EntityId, using hm: HomeManagable) async throws -> EntityStorageItem? {
        do {
            return try await hm.getCurrentEntity(with: entityId)
        } catch OptionalError.notFound {
            return nil
        }
    }

    private func endQuestion(using hm: HomeManagable) async {
        log.info("Ending the fireplace question on every device")
        await hm.deliver(.endLiveActivities(activityType: FireplaceContentState.activityTypeName, finalContentState: FireplaceContentState.ended))
    }
}

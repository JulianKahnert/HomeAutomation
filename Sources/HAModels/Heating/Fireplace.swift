//
//  Fireplace.swift
//  HAModels
//

import Foundation

/// Whether the fireplace burns right now (glossary: fireplace mode) and where its question stands.
public struct FireplaceState: Sendable, Equatable {
    public let isOn: Bool
    /// When the fireplace was switched on; `nil` while it is off.
    public let since: Date?
    /// When the server asks "Ist der Kamin noch an?" (or asked, while ``isAsking``); `nil` while it is off.
    public let asksAt: Date?
    /// Whether the question is open: the Live Activity waits for an answer.
    public let isAsking: Bool
    /// When the server ends the fireplace by itself if nobody answers: `Fireplace.answerTimeout` after ``asksAt``;
    /// `nil` while it is off.
    public let endsAt: Date?

    /// - Parameters:
    ///   - asksAt: The question the server named; `nil` derives it from `since` and `Fireplace.maxDuration`.
    ///   - endsAt: The end the server named; `nil` derives it from `asksAt` and `Fireplace.answerTimeout`.
    public init(isOn: Bool, since: Date? = nil, asksAt: Date? = nil, isAsking: Bool = false, endsAt: Date? = nil) {
        self.isOn = isOn
        self.since = since
        let asksAt = asksAt ?? since.map { $0.addingTimeInterval(Fireplace.maxDuration) }
        self.asksAt = asksAt
        self.isAsking = isAsking
        self.endsAt = endsAt ?? asksAt.map { $0.addingTimeInterval(Fireplace.answerTimeout) }
    }

    public static let off = FireplaceState(isOn: false)
}

/// The fireplace mode: a server-owned switch entity (`Fireplace.stateId`), set from the FlowKit Controller app
/// (the Heizung tab, the push action "Kamin an?" and the answer "Nein" of the question) with origin `app`, and
/// ended by `FireplaceTimeout` with origin `server` when nobody answers the question. Rooms read it like a window
/// contact (`RoomContact.fireplace`); a change reaches them as an ordinary `HomeEvent.change`.
///
/// The question "Ist der Kamin noch an?" (glossary: fireplace question) lives in a second server-owned entity,
/// `Fireplace.questionId`, a ``Deadline``: `running(until:)` names the moment of the next question after an
/// answer "Ja", `overdue(since:)` says the question is open since then. A question item older than the switch-on
/// belongs to an earlier fire and counts as none.
public enum Fireplace {
    /// The server asks whether the fireplace still burns this long after it was switched on, and again this long
    /// after each answer "Ja".
    public static let maxDuration: TimeInterval = 2 * 3600
    /// Without an answer the server switches the fireplace off this long after it asked.
    public static let answerTimeout: TimeInterval = 30 * 60

    /// The fireplace entity: server-owned, a switch (on = burning). The app may set it: a switch is a kind the app may set (``ValueDescriptor/isSettableFromApp``).
    public static let stateId = EntityId.serverOwned(name: "fireplace", characteristic: .switcher)
    /// The question entity: server-owned, a deadline (see the type's documentation). Its name has no slash, so
    /// the window Live Activity does not take it for a window. The app answers through `POST /heating/fireplace/answer`.
    public static let questionId = EntityId.serverOwned(name: "fireplace", characteristic: .deadline)

    /// Category of the push "Kamin an?"; the app registers its action under this name.
    public static let notificationCategory = "FIREPLACE_ASK"
    /// The action of that category that switches the fireplace on.
    public static let switchOnActionId = "FIREPLACE_ON"
    /// Collapse id of the reminder "Kamin an?"; apart from `notificationId` so the end push does not count against its rate limit.
    public static let reminderNotificationId = "fireplace-reminder"
    /// Collapse id of the fireplace pushes, so a newer one replaces an older.
    public static let notificationId = "fireplace"

    /// The state the server holds, since the last change of the entities (a repeated value keeps it). It does not
    /// depend on HomeKit: a degraded HomeKit stops the radiator writes, not the fire.
    /// - Throws: Any failure of reading the state; only an entity the server never held is `.off` (or no question).
    public static func state(with homeManager: HomeManagable) async throws -> FireplaceState {
        let item: EntityStorageItem
        do {
            item = try await homeManager.getCurrentEntity(with: stateId)
        } catch OptionalError.notFound {
            return .off
        }
        let question: EntityStorageItem?
        do {
            question = try await homeManager.getCurrentEntity(with: questionId)
        } catch OptionalError.notFound {
            question = nil
        }
        return state(of: item, question: question)
    }

    /// The state the database holds, for the API: the same derivation as ``state(with:)``.
    public static func state(from storage: any StorageRepository) async throws -> FireplaceState {
        state(of: try await storage.getCurrent(stateId), question: try await storage.getCurrent(questionId))
    }

    /// The state a stored fireplace item and question item stand for; `nil` (never held) is off, or no question.
    public static func state(of item: EntityStorageItem?, question: EntityStorageItem? = nil) -> FireplaceState {
        guard let item, item.isDeviceOn == true else { return .off }
        // A question of an earlier fire does not count: the fire started after it.
        guard let question, question.timestamp >= item.timestamp, let deadline = question.deadline else {
            return FireplaceState(isOn: true, since: item.timestamp)
        }
        switch deadline {
        case .none:
            return FireplaceState(isOn: true, since: item.timestamp)
        case .running(let until):
            return FireplaceState(isOn: true, since: item.timestamp, asksAt: until)
        case .overdue(let since):
            return FireplaceState(isOn: true, since: item.timestamp, asksAt: since, isAsking: true)
        }
    }
}

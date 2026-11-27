//
//  FireplaceTimeout.swift
//  HAImplementations
//

import Foundation
import HAModels

/// Ends the fireplace `Fireplace.maxDuration` after it was switched on, with a push (glossary: fireplace end).
///
/// The duration counts from the switch-on time the server stored, so a server restart does not restart it.
/// Ending it reports the entity off (origin `server`), which tells the rooms that follow the fireplace to return to their plan.
/// The push goes out only when this run switched it off: the next tick finds it off, so it is sent once per
/// time the fireplace was on.
public struct FireplaceTimeout: Automatable {
    public var isActive = true
    public let name: String

    public var triggerEntityIds: Set<EntityId> { [] }

    public init(_ name: String = "fireplace-timeout") {
        self.name = name
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        guard case .time(let date) = event else { return false }
        return await hasExpired(at: date, using: hm)
    }

    public func execute(using hm: HomeManagable) async throws {
        try await execute(using: hm, now: Date())
    }

    func execute(using hm: HomeManagable, now: Date) async throws {
        // look again: the fireplace may have gone off since the trigger
        guard await hasExpired(at: now, using: hm),
              await hm.report(Fireplace.stateId, value: .bool(false), origin: .server) else { return }
        await hm.deliver(.push(title: "Kamin aus",
                               message: "Der Kamin war \(Self.durationText(Fireplace.maxDuration)) an und wurde ausgeschaltet. Die Heizkörper folgen wieder dem Plan.",
                               id: Fireplace.notificationId))
    }

    /// The duration in German for the push, rounded to whole minutes: "2 Stunden", "1 Stunde und 30 Minuten", "45 Minuten".
    static func durationText(_ duration: TimeInterval) -> String {
        let minutes = max(Int((duration / 60).rounded()), 0)
        let hours = minutes / 60
        let rest = minutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append(hours == 1 ? "1 Stunde" : "\(hours) Stunden") }
        if rest > 0 || hours == 0 { parts.append(rest == 1 ? "1 Minute" : "\(rest) Minuten") }
        return parts.joined(separator: " und ")
    }

    private func hasExpired(at date: Date, using hm: HomeManagable) async -> Bool {
        guard let endsAt = await Fireplace.state(with: hm).endsAt else { return false }
        return date >= endsAt
    }
}

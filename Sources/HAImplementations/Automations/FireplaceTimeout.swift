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

    public init(_ name: String = "fireplace-timeout") {
        self.name = name
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        guard case .time(let date) = event else { return false }
        return try await hasExpired(at: date, using: hm)
    }

    public func execute(using hm: HomeManagable) async throws {
        try await execute(using: hm, now: Date())
    }

    func execute(using hm: HomeManagable, now: Date) async throws {
        // Decided where the state is set: the fireplace may have gone off, or the app switched it off and on again
        // (a new start), since the trigger, and that start must not be ended by this run.
        guard try await hm.report(Fireplace.stateId, value: .bool(false), origin: .server, ifCurrent: { item in
            Fireplace.state(of: item).endsAt.map { now >= $0 } ?? false
        }) else { return }
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

    private func hasExpired(at date: Date, using homeManager: HomeManagable) async throws -> Bool {
        guard let endsAt = try await Fireplace.state(with: homeManager).endsAt else { return false }
        return date >= endsAt
    }
}

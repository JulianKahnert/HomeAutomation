import Foundation
import SwiftUI

// Mock domain for the heating debug views. Mirrors the heating map decisions:
// a room has n windows, m radiators and at most one external sensor; priority
// window open > fireplace > plan; Soll = plan + offset per radiator; "off" is
// HeaterCooler Active = 0; every server write carries a `reason`.

public struct Sample: Sendable {
    public let date: Date
    public let value: Double
}

/// Why a radiator is (or is not) warm. One kind per question the debug view must answer.
public enum CauseKind: String, CaseIterable, Sendable {
    case window, fireplace, planSetback, manual, modeOff, valveClosed, sensorFailure, heatPump, offset, heating

    var label: String {
        switch self {
        case .window: "Fenster offen"
        case .fireplace: "Kamin an"
        case .planSetback: "Plan-Absenkung"
        case .manual: "Manuelle Änderung"
        case .modeOff: "Modus Aus"
        case .valveClosed: "Ventil zu"
        case .sensorFailure: "Raumsensor ausgefallen"
        case .heatPump: "Wärmepumpe liefert nicht"
        case .offset: "Offset"
        case .heating: "Heizt nach Plan"
        }
    }

    var symbol: String {
        switch self {
        case .window: "window.vertical.open"
        case .fireplace: "flame"
        case .planSetback: "moon.zzz"
        case .manual: "hand.point.up.left"
        case .modeOff: "power"
        case .valveClosed: "spigot"
        case .sensorFailure: "sensor.tag.radiowaves.forward"
        case .heatPump: "heat.waves"
        case .offset: "plusminus"
        case .heating: "checkmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .window: .orange
        case .fireplace: .brown
        case .planSetback: .indigo
        case .manual: .pink
        case .modeOff: .gray
        case .valveClosed: .cyan
        case .sensorFailure: .yellow
        case .heatPump: .mint
        case .offset: .purple
        case .heating: .green
        }
    }
}

public struct Cause: Identifiable, Sendable {
    public let id = UUID()
    let kind: CauseKind
    /// One-line answer, e.g. "Fenster Küche offen".
    let title: String
    /// What the server did / what follows, e.g. "→ Modus Aus (Active = 0)".
    let detail: String
    let since: Date?
    /// Next change the user can expect, e.g. "Auto-Ende 03:30".
    var until: String?
}

public enum RadiatorStatus: Sendable {
    case cold, warm, warning

    var color: Color {
        switch self {
        case .cold: .blue
        case .warm: .red
        case .warning: .yellow
        }
    }

    var label: String {
        switch self {
        case .cold: "kalt"
        case .warm: "heizt"
        case .warning: "prüfen"
        }
    }
}

public struct Radiator: Identifiable, Sendable {
    public let id: String
    let name: String
    let roomID: String
    /// Per-radiator offset from the Swift config (±3 °C).
    let offset: Double
    let isOnFireplaceList: Bool
    let eveIst: [Sample]
    /// Step series of the Soll the thermostat holds (written by server or by hand).
    let soll: [Sample]
    let valve: [Sample]
    /// Intervals with HeaterCooler Active = 0.
    let offIntervals: [DateInterval]
    let status: RadiatorStatus
    /// Ordered: the first cause is the answer, the rest is context.
    let causes: [Cause]

    var currentEveIst: Double { eveIst.last?.value ?? .nan }
    var currentSoll: Double { soll.last?.value ?? .nan }
    var currentValve: Double { valve.last?.value ?? .nan }
    var isOff: Bool { offIntervals.contains { $0.end >= MockData.now } }
}

public struct WindowContact: Identifiable, Sendable {
    public var id: String { name }
    let name: String
    let openIntervals: [DateInterval]
    var isOpen: Bool { openIntervals.contains { $0.end >= MockData.now } }
}

public struct RoomSensor: Sendable {
    let name: String
    let values: [Sample]
    /// Failure per the map rule: unreachable, read error, or no value for > 3 h.
    let failedSince: Date?
}

public struct PlanPoint: Sendable {
    let time: String
    let soll: Double
    let label: String
}

public struct Room: Identifiable, Sendable {
    public let id: String
    let name: String
    let windows: [WindowContact]
    let sensor: RoomSensor?
    let fireplaceOn: [DateInterval]
    let plan: [PlanPoint]
    /// Index into `plan` of the switch point that is active now.
    let activePlanIndex: Int
    let radiators: [Radiator]

    var activePlan: PlanPoint { plan[activePlanIndex] }
    var nextPlan: PlanPoint { plan[(activePlanIndex + 1) % plan.count] }
    var isFireplaceOn: Bool { fireplaceOn.contains { $0.end >= MockData.now } }
}

/// One line of the action log. `reason` is the new field from ticket 14;
/// observations and pushes are derived from the history, not written by the server.
public struct LogEntry: Identifiable, Sendable {
    public enum Kind: Sendable { case write, observation, push }

    public let id = UUID()
    let date: Date
    let roomID: String
    let radiatorID: String?
    let kind: Kind
    /// What happened, e.g. "Soll 16,0 °C" or "Modus Aus (Active = 0)".
    let action: String
    /// The `reason` field value (plan, fenster, fensterZu, kamin, kaminAus, kaminTimeout) or nil for observations.
    let reason: String?
    /// `detailDescription`: plan Soll + offset, trigger device, …
    let detail: String
    let causeKind: CauseKind
}

// MARK: - Derived "seit wann" answers

extension [Sample] {
    /// Start of the trailing run of equal values: answers "seit wann bei Z?".
    func steadySince(tolerance: Double = 0.01) -> Date? {
        guard let last else { return nil }
        var start = last.date
        for sample in reversed() {
            guard abs(sample.value - last.value) <= tolerance else { break }
            start = sample.date
        }
        return start
    }

    func values(in domain: ClosedRange<Date>) -> [Sample] {
        filter { domain.contains($0.date) }
    }
}

// MARK: - Formatting (German)

enum Fmt {
    static let de = Locale(identifier: "de_DE")

    static func temp(_ value: Double) -> String {
        value.isNaN ? "–" : value.formatted(.number.precision(.fractionLength(1)).locale(de)) + " °C"
    }

    static func signed(_ value: Double) -> String {
        (value >= 0 ? "+" : "−") + abs(value).formatted(.number.precision(.fractionLength(1)).locale(de)) + " °C"
    }

    static func percent(_ value: Double) -> String {
        value.isNaN ? "–" : "\(Int(value)) %"
    }

    static func time(_ date: Date) -> String {
        date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(de))
    }

    /// "seit 22:25 (15 min)" – the clock time plus the running duration.
    static func since(_ date: Date, now: Date = MockData.now) -> String {
        let prefix = Calendar.current.isDate(date, inSameDayAs: now) ? "" : "gestern "
        return "seit \(prefix)\(time(date)) (\(duration(now.timeIntervalSince(date))))"
    }

    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}

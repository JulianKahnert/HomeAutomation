import Foundation
import SwiftUI

// Mock domain for variant E (Skizze v3). Rooms and device names are the real ones:
// PlaceIds and the Eve Thermos of Küche, Esszimmer and Kaminzimmer from
// HomeAutomation-config/Devices.swift, plus the thermos the live check of 15.11.2026
// found in HomeKit (Bad OG, Arbeitszimmer, Schlafzimmer "Heizung links").
// Values are simulated: a lag model per 10 min over the last 7 days.

enum V3EventKind: String, CaseIterable, Sendable {
    case plan, window, fireplace, manual, system

    var emoji: String {
        switch self {
        case .plan: "📅"
        case .window: "🪟"
        case .fireplace: "🔥"
        case .manual: "✋"
        case .system: "⚙︎"
        }
    }

    var label: String {
        switch self {
        case .plan: "Plan"
        case .window: "Fenster"
        case .fireplace: "Kamin"
        case .manual: "manuell/beobachtet"
        case .system: "System"
        }
    }

    var color: Color {
        switch self {
        case .plan: .indigo
        case .window: .teal
        case .fireplace: .orange
        case .manual: .purple
        case .system: .gray
        }
    }
}

struct V3Event: Identifiable, Sendable {
    let roomID: String
    let kind: V3EventKind
    let date: Date
    /// Window open or fireplace on: drawn as a tinted band over the full height.
    var end: Date?
    /// What happened, e.g. "Soll 21,0 → 23,0 °C am Gerät".
    let title: String
    /// The `reason` tag the server writes, or the observation tag for derived events.
    let reason: String

    /// Where the pin sits; differs from `date` only for a band clipped by the range.
    var pinDate: Date?

    var id: String { "\(roomID)-\(kind.rawValue)-\(Int(date.timeIntervalSince1970))" }
    var pinX: Date { pinDate ?? date }

    func pinned(at date: Date) -> V3Event {
        var copy = self
        copy.pinDate = date
        return copy
    }
}

struct V3Sample: Sendable {
    let date: Date
    let soll: Double
    /// nil while the thermo sends no value.
    let ist: Double?
    /// nil while the thermo sends nothing: the valve comes from the same device.
    let valve: Double?
}

struct V3Room: Identifiable, Sendable {
    let id: String
    /// PlaceId as in Devices.swift.
    let placeId: String
    /// Human-readable German name for the UI.
    let name: String
    /// Short x-axis label of the overview chart.
    let short: String
    /// Accessory name of the thermostat (HeaterCooler) in HomeKit.
    let thermo: String
    let windowContacts: [String]
    let samples: [V3Sample]
    let events: [V3Event]
    let sensorDownSince: Date?

    var current: V3Sample { samples.last! }
    var delta: Double? { current.ist.map { $0 - current.soll } }
    var lastIst: V3Sample? { samples.last { $0.ist != nil } }

    func sample(at date: Date) -> V3Sample {
        samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }!
    }
}

enum V3Range: String, CaseIterable, Identifiable, Sendable {
    case twoHours = "2 h"
    case day = "24 h"
    case week = "7 T"

    var id: String { rawValue }

    var interval: TimeInterval {
        switch self {
        case .twoHours: 2 * 3_600
        case .day: 24 * 3_600
        case .week: 7 * 86_400
        }
    }

    var domain: ClosedRange<Date> { V3Data.now.addingTimeInterval(-interval)...V3Data.now }
}

enum V3Data {
    static let calendar = Calendar.current
    static let now = MockData.now
    static let weekStart = now.addingTimeInterval(-7 * 86_400)
    static let grid: [Date] = stride(from: 0.0, through: 7 * 86_400, by: 600).map { weekStart.addingTimeInterval($0) }

    /// "dd.MM. HH:mm" in the mock week (November 2026).
    static func d(_ day: Int, _ hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: parts[0], minute: parts[1]))!
    }

    static let days = Array(8...15)

    // MARK: Room setup

    private struct Setup {
        let id, placeId, name, short, thermo: String
        let windows: [String]
        /// (hh:mm, Soll, Label), repeats daily.
        let plan: [(String, Double, String)]
        var windowOpen: [DateInterval] = []
        var fireplace: [DateInterval] = []
        /// Manual Soll at the device: (start, end, value).
        var manual: [(Date, Date, Double)] = []
        var valveStuckSince: Date?
        var sensorDownSince: Date?
        /// Eve measures at the radiator: a constant bias versus the plan target.
        var bias: Double = 0
        var startIst: Double = 19
        var extraEvents: [V3Event] = []
    }

    private static func daily(_ from: String, _ to: String, days: [Int] = days) -> [DateInterval] {
        days.compactMap { day in
            let start = d(day, from)
            var end = d(day, to)
            if end < start { end = end.addingTimeInterval(86_400) }
            guard start < now else { return nil }
            return DateInterval(start: start, end: min(end, now))
        }
        .filter { $0.end > weekStart }
    }

    private static let fireplaceEvenings: [DateInterval] = [
        DateInterval(start: d(9, "18:45"), end: d(9, "23:10")),
        DateInterval(start: d(12, "19:15"), end: d(13, "00:05")),
        DateInterval(start: d(14, "17:30"), end: d(14, "22:50")),
        DateInterval(start: d(15, "19:30"), end: now),
    ]

    private static let setups: [Setup] = [
        Setup(
            id: "kueche", placeId: "Küche", name: "Küche", short: "Küche", thermo: "Eve Thermo",
            windows: ["Fenster Links", "Fenster Rechts"],
            plan: [("06:00", 21, "Tag"), ("23:00", 18, "Nacht")],
            windowOpen: daily("07:05", "07:15") + [DateInterval(start: d(15, "12:10"), end: d(15, "12:25")), DateInterval(start: d(15, "22:25"), end: now)],
            startIst: 18.2
        ),
        Setup(
            id: "bad-og", placeId: "Bad - OG", name: "Bad OG", short: "Bad OG", thermo: "Eve Thermo Bad OG",
            windows: ["Fenster"],
            plan: [("05:30", 22, "Morgen"), ("09:00", 19, "Tag"), ("17:00", 22, "Abend"), ("23:00", 18, "Nacht")],
            windowOpen: daily("06:50", "07:05"),
            valveStuckSince: d(15, "14:10"),
            startIst: 18.4,
            extraEvents: [
                V3Event(roomID: "bad-og", kind: .system, date: d(15, "17:10"), title: "Ventil 0 % trotz Soll 22,0 °C > Ist", reason: "beobachtet · ventilHaengt"),
            ]
        ),
        Setup(
            id: "arbeitszimmer", placeId: "Julians Arbeitszimmer", name: "Arbeitszimmer", short: "Arbeit", thermo: "Eve Thermo Arbeitszimmer",
            windows: ["Fenster"],
            plan: [("07:00", 21, "Tag"), ("23:00", 18, "Nacht")],
            manual: [(d(11, "20:15"), d(11, "23:00"), 22.5), (d(15, "21:40"), now, 23)],
            bias: 0.3,
            startIst: 18.5
        ),
        Setup(
            id: "schlafzimmer", placeId: "Schlafzimmer", name: "Schlafzimmer", short: "Schlaf", thermo: "Heizung links",
            windows: ["Fenster links", "Fenster rechts"],
            plan: [("06:30", 20, "Morgen"), ("09:00", 17.5, "Tag"), ("21:00", 17, "Nacht")],
            windowOpen: daily("07:10", "07:30"),
            bias: 0.2,
            startIst: 17.2
        ),
        Setup(
            id: "esszimmer", placeId: "Esszimmer", name: "Esszimmer", short: "Essen", thermo: "Eve Thermo",
            windows: [],
            plan: [("06:00", 20, "Tag"), ("23:00", 18, "Nacht")],
            fireplace: fireplaceEvenings,
            startIst: 18.3
        ),
        Setup(
            id: "kaminzimmer", placeId: "Kaminzimmer", name: "Kaminzimmer", short: "Kamin", thermo: "Eve Thermo",
            windows: [],
            plan: [("07:00", 21, "Tag"), ("23:00", 18, "Nacht")],
            fireplace: fireplaceEvenings,
            sensorDownSince: d(10, "14:50"),
            startIst: 18.6,
            extraEvents: [
                V3Event(roomID: "kaminzimmer", kind: .system, date: d(10, "17:50"), title: "Push „Eve Thermo Kaminzimmer sendet keine Werte“ (> 3 h)", reason: "sensorAusfall"),
            ]
        ),
    ]

    /// Real system events of 15.11.2026 that touch every room.
    private static func globalEvents(_ roomID: String) -> [V3Event] {
        [
            V3Event(roomID: roomID, kind: .system, date: d(15, "20:04"), title: "Server neu deployt (80cc917)", reason: "deploy"),
            V3Event(roomID: roomID, kind: .system, date: d(15, "21:02"), title: "Adapter Build 214 verbunden", reason: "adapter"),
        ]
    }

    // MARK: Simulation

    private static func planSoll(_ setup: Setup, at date: Date) -> (Double, String) {
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let points = setup.plan.map { point -> (Int, Double, String) in
            let parts = point.0.split(separator: ":").compactMap { Int($0) }
            return (parts[0] * 60 + parts[1], point.1, point.2)
        }
        let active = points.last { $0.0 <= minutes } ?? points.last!
        return (active.1, active.2)
    }

    private static func build(_ setup: Setup) -> V3Room {
        var ist = setup.startIst
        var samples: [V3Sample] = []
        for (index, date) in grid.enumerated() {
            let manual = setup.manual.first { $0.0 <= date && (date < $0.1 || $0.1 >= now) }
            let soll = manual?.2 ?? planSoll(setup, at: date).0
            let windowOpen = setup.windowOpen.contains { $0.contains(date) }
            let fireplaceOn = setup.fireplace.contains { $0.contains(date) }
            let stuck = setup.valveStuckSince.map { date >= $0 } ?? false

            let target: Double
            let alpha: Double
            if windowOpen {
                (target, alpha) = (12, 0.15)
            } else if fireplaceOn {
                (target, alpha) = (23 + setup.bias, 0.07)
            } else if stuck {
                (target, alpha) = (19.8, 0.03)
            } else {
                let goal = soll + setup.bias
                (target, alpha) = (goal, ist < goal ? 0.08 : 0.035)
            }
            // Deterministic wobble so the lines do not look drawn with a ruler.
            let wobble = 0.06 * sin(Double(index) * 0.7 + Double(setup.id.count))
            ist += alpha * (target - ist) + wobble * 0.3

            let off = windowOpen || fireplaceOn
            var valve = 0.0
            if !off && !stuck {
                valve = min(max((soll - ist) * 45 + 12, 0), 100)
                if ist > soll + 0.3 { valve = 0 }
                valve = (valve / 5).rounded() * 5
            }
            let down = setup.sensorDownSince.map { date >= $0 } ?? false
            samples.append(V3Sample(date: date, soll: soll, ist: down ? nil : (ist * 10).rounded() / 10, valve: down ? nil : valve))
        }
        return V3Room(
            id: setup.id, placeId: setup.placeId, name: setup.name, short: setup.short, thermo: setup.thermo,
            windowContacts: setup.windows, samples: samples, events: events(setup),
            sensorDownSince: setup.sensorDownSince
        )
    }

    private static func events(_ setup: Setup) -> [V3Event] {
        var events: [V3Event] = []
        for day in days {
            for point in setup.plan {
                let date = d(day, point.0)
                guard date > weekStart, date <= now else { continue }
                let fmt = Fmt.temp(point.1)
                events.append(V3Event(roomID: setup.id, kind: .plan, date: date, title: "Plan \(point.2): Soll \(fmt)", reason: "plan"))
            }
        }
        let contact = setup.windows.first ?? "Fenster"
        for interval in setup.windowOpen {
            let isOpen = interval.end >= now
            events.append(V3Event(
                roomID: setup.id, kind: .window, date: interval.start, end: interval.end,
                title: "\(contact) offen → Modus Aus" + (isOpen ? " (noch offen)" : ", zu um \(Fmt.time(interval.end))"),
                reason: "fenster"
            ))
        }
        for interval in setup.fireplace {
            let isOn = interval.end >= now
            events.append(V3Event(
                roomID: setup.id, kind: .fireplace, date: interval.start, end: interval.end,
                title: "Kamin an → Modus Aus (Kamin-Liste)" + (isOn ? ", Auto-Ende 03:30" : ", aus um \(Fmt.time(interval.end))"),
                reason: "kamin"
            ))
        }
        for manual in setup.manual {
            let plan = planSoll(setup, at: manual.0).0
            events.append(V3Event(
                roomID: setup.id, kind: .manual, date: manual.0,
                title: "Soll \(Fmt.temp(plan)) → \(Fmt.temp(manual.2)) am Gerät",
                reason: "beobachtet · übersteuert"
            ))
        }
        events += setup.extraEvents + globalEvents(setup.id)
        return events.sorted { $0.date < $1.date }
    }

    static let rooms: [V3Room] = setups.map { build($0) }

    /// Coldest first; a room without a value goes last.
    static var sortedRooms: [V3Room] {
        rooms.sorted { ($0.delta ?? .infinity) < ($1.delta ?? .infinity) }
    }

    static func room(_ id: String) -> V3Room { rooms.first { $0.id == id }! }

    // MARK: Heatmap

    struct Cell: Identifiable, Sendable {
        let roomID: String
        let roomShort: String
        let hour: Date
        let delta: Double?
        var id: String { "\(roomID)-\(Int(hour.timeIntervalSince1970))" }
    }

    /// Mean Δ per room and hour over the week; nil for hours without an Ist value.
    static let heatmap: [Cell] = rooms.flatMap { room in
        Dictionary(grouping: room.samples) { calendar.dateInterval(of: .hour, for: $0.date)!.start }
            .map { hour, samples in
                let deltas = samples.compactMap { sample in sample.ist.map { $0 - sample.soll } }
                return Cell(roomID: room.id, roomShort: room.short, hour: hour, delta: deltas.isEmpty ? nil : deltas.reduce(0, +) / Double(deltas.count))
            }
    }
}

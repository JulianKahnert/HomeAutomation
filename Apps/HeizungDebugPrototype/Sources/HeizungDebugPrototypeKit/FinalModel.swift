import Foundation
import SwiftUI

// Mock domain for variant F (final design). Same rooms, plans and week as variant E, but
// shaped like the agreed API: `GET /heating/overview` (Δ, Ist, Plan-Soll, Ist source, heatmap)
// and `GET /heating/rooms/{placeId}?range=` (ist, sollPlan, valve per radiator, events).
// Δ is Ist minus the room's Plan-Soll, not the radiator Soll with manual changes or offset.

enum FEventKind: String, CaseIterable, Sendable {
    case plan, window, fireplace, observed, system

    var symbol: String {
        switch self {
        case .plan: "calendar"
        case .window: "window.vertical.open"
        case .fireplace: "flame"
        case .observed: "hand.raised"
        case .system: "gearshape"
        }
    }

    var label: String {
        switch self {
        case .plan: "Plan"
        case .window: "Fenster"
        case .fireplace: "Kamin"
        case .observed: "beobachtet"
        case .system: "System"
        }
    }
}

struct FEvent: Identifiable, Sendable {
    let kind: FEventKind
    let date: Date
    /// Window open or fireplace on: drawn as an area over the full plot height.
    var end: Date?
    let title: String
    /// The `reason` the server wrote, or the observation tag.
    let reason: String
    /// Where the pin sits; differs from `date` only for an area clipped by the range.
    var pinDate: Date?

    var id: String { "\(kind.rawValue)-\(Int(date.timeIntervalSince1970))" }
    var pinX: Date { pinDate ?? date }
}

/// Where the room's Ist comes from: the external sensor, else the mean of its thermostats.
enum FIstSource: Sendable {
    case roomSensor(String)
    case thermostats([String])

    var symbol: String {
        switch self {
        case .roomSensor: "thermometer.medium"
        case .thermostats: "heater.vertical"
        }
    }

    var text: String {
        switch self {
        case .roomSensor(let name): "Raumsensor „\(name)“"
        case .thermostats(let names) where names.count == 1: "Thermostat „\(names[0])“"
        case .thermostats(let names): "Mittel aus \(names.count) Thermostaten"
        }
    }
}

struct FSample: Sendable {
    let date: Date
    let sollPlan: Double
    /// nil while the source sends no value.
    let ist: Double?
    /// Valve % per radiator, same order as `FRoom.radiators`; nil while the thermo is silent.
    let valves: [Double?]

    var delta: Double? { ist.map { $0 - sollPlan } }
}

struct FRoom: Identifiable, Sendable {
    let id: String
    let placeId: String
    let name: String
    /// Axis label of the overview bars.
    let short: String
    let radiators: [String]
    let istSource: FIstSource
    let samples: [FSample]
    let events: [FEvent]

    var current: FSample { samples.last! }
    var delta: Double? { current.delta }
    var lastIst: FSample? { samples.last { $0.ist != nil } }

    func sample(at date: Date) -> FSample {
        samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }!
    }
}

enum FRange: String, CaseIterable, Identifiable, Sendable {
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

    var domain: ClosedRange<Date> { FData.now.addingTimeInterval(-interval)...FData.now }
}

/// One heatmap cell: room × day × six-hour segment.
struct FCell: Identifiable, Sendable {
    let roomID: String
    let day: Date
    /// 0 = 0–6, 1 = 6–12, 2 = 12–18, 3 = 18–24 Uhr.
    let segment: Int
    /// Mean Δ; nil when more than half of the segment has no Ist.
    let delta: Double?

    var id: String { "\(roomID)-\(Int(day.timeIntervalSince1970))-\(segment)" }

    var segmentLabel: String { ["0–6", "6–12", "12–18", "18–24"][segment] + " Uhr" }
}

enum FData {
    static let calendar = Calendar.current
    static let now = MockData.now
    static let weekStart = now.addingTimeInterval(-7 * 86_400)
    static let grid: [Date] = stride(from: 0.0, through: 7 * 86_400, by: 600).map { weekStart.addingTimeInterval($0) }

    static func d(_ day: Int, _ hhmm: String) -> Date {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: parts[0], minute: parts[1]))!
    }

    static let days = Array(8...15)
    /// The seven heatmap days, oldest first.
    static let heatmapDays: [Date] = (9...15).map { d($0, "00:00") }

    private struct Setup {
        let id, placeId, name, short: String
        let radiators: [String]
        let istSource: FIstSource
        let window: String?
        let plan: [(String, Double, String)]
        var windowOpen: [DateInterval] = []
        var fireplace: [DateInterval] = []
        /// Soll changed at the device: (start, end, value). Heats the room, Plan-Soll stays.
        var manual: [(Date, Date, Double)] = []
        var valveStuckSince: Date?
        var sensorDownSince: Date?
        var bias: Double = 0
        var startIst: Double = 19
        var extraEvents: [FEvent] = []
    }

    private static func daily(_ from: String, _ to: String) -> [DateInterval] {
        days.compactMap { day in
            let start = d(day, from)
            let end = d(day, to)
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
            id: "kueche", placeId: "Küche", name: "Küche", short: "Küche",
            radiators: ["Eve Thermo"], istSource: .roomSensor("Küche Sensor"), window: "Fenster Links",
            plan: [("06:00", 21, "Tag"), ("23:00", 18, "Nacht")],
            windowOpen: daily("07:05", "07:15") + [DateInterval(start: d(15, "12:10"), end: d(15, "12:25")), DateInterval(start: d(15, "22:25"), end: now)],
            startIst: 18.2
        ),
        Setup(
            id: "bad-og", placeId: "Bad - OG", name: "Bad OG", short: "Bad OG",
            radiators: ["Eve Thermo Bad OG"], istSource: .thermostats(["Eve Thermo Bad OG"]), window: "Fenster",
            plan: [("05:30", 22, "Morgen"), ("09:00", 19, "Tag"), ("17:00", 22, "Abend"), ("23:00", 18, "Nacht")],
            windowOpen: daily("06:50", "07:05"),
            valveStuckSince: d(15, "14:10"),
            startIst: 18.4,
            extraEvents: [
                FEvent(kind: .system, date: d(15, "17:10"), title: "Ventil 0 % trotz Soll 22,0 °C über Ist", reason: "ventilHaengt"),
            ]
        ),
        Setup(
            id: "arbeitszimmer", placeId: "Julians Arbeitszimmer", name: "Arbeitszimmer", short: "Arbeit",
            radiators: ["Eve Thermo Arbeitszimmer"], istSource: .roomSensor("Arbeitszimmer Sensor"), window: "Fenster",
            plan: [("07:00", 21, "Tag"), ("23:00", 18, "Nacht")],
            manual: [(d(11, "20:15"), d(11, "23:00"), 22.5), (d(15, "21:40"), now, 23)],
            startIst: 18.5
        ),
        Setup(
            id: "schlafzimmer", placeId: "Schlafzimmer", name: "Schlafzimmer", short: "Schlaf",
            radiators: ["Heizung links", "Heizung rechts"], istSource: .thermostats(["Heizung links", "Heizung rechts"]), window: "Fenster links",
            plan: [("06:30", 20, "Morgen"), ("09:00", 17.5, "Tag"), ("21:00", 17, "Nacht")],
            windowOpen: daily("07:10", "07:30"),
            startIst: 17.2
        ),
        Setup(
            id: "esszimmer", placeId: "Esszimmer", name: "Esszimmer", short: "Essen",
            radiators: ["Eve Thermo"], istSource: .thermostats(["Eve Thermo"]), window: nil,
            plan: [("06:00", 20, "Tag"), ("23:00", 18, "Nacht")],
            fireplace: fireplaceEvenings,
            startIst: 18.3
        ),
        Setup(
            id: "kaminzimmer", placeId: "Kaminzimmer", name: "Kaminzimmer", short: "Kamin",
            radiators: ["Eve Thermo"], istSource: .thermostats(["Eve Thermo"]), window: nil,
            plan: [("07:00", 21, "Tag"), ("23:00", 18, "Nacht")],
            fireplace: fireplaceEvenings,
            sensorDownSince: d(10, "14:50"),
            startIst: 18.6,
            extraEvents: [
                FEvent(kind: .system, date: d(10, "17:50"), title: "Push: „Eve Thermo“ im Kaminzimmer sendet keine Werte (> 3 h)", reason: "sensorAusfall"),
            ]
        ),
    ]

    private static let globalEvents: [FEvent] = [
        FEvent(kind: .system, date: d(15, "20:04"), title: "Server neu deployt (80cc917)", reason: "deploy"),
        FEvent(kind: .system, date: d(15, "21:02"), title: "Adapter Build 214 verbunden", reason: "adapter"),
    ]

    private static func planSoll(_ setup: Setup, at date: Date) -> (Double, String) {
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let points = setup.plan.map { point -> (Int, Double, String) in
            let parts = point.0.split(separator: ":").compactMap { Int($0) }
            return (parts[0] * 60 + parts[1], point.1, point.2)
        }
        let active = points.last { $0.0 <= minutes } ?? points.last!
        return (active.1, active.2)
    }

    private static func build(_ setup: Setup) -> FRoom {
        var ist = setup.startIst
        var samples: [FSample] = []
        for (index, date) in grid.enumerated() {
            let plan = planSoll(setup, at: date).0
            let manual = setup.manual.first { $0.0 <= date && (date < $0.1 || $0.1 >= now) }
            let deviceSoll = manual?.2 ?? plan
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
                let goal = deviceSoll + setup.bias
                (target, alpha) = (goal, ist < goal ? 0.08 : 0.035)
            }
            let wobble = 0.06 * sin(Double(index) * 0.7 + Double(setup.id.count))
            ist += alpha * (target - ist) + wobble * 0.3

            var valve = 0.0
            if !(windowOpen || fireplaceOn || stuck) {
                valve = min(max((deviceSoll - ist) * 45 + 12, 0), 100)
                if ist > deviceSoll + 0.3 { valve = 0 }
            }
            let down = setup.sensorDownSince.map { date >= $0 } ?? false
            // The second radiator sits under the window and opens a little further.
            let valves: [Double?] = setup.radiators.indices.map { radiator in
                guard !down else { return nil }
                let value = radiator == 0 ? valve : (valve > 0 ? min(valve + 15, 100) : 0)
                return (value / 5).rounded() * 5
            }
            samples.append(FSample(date: date, sollPlan: plan, ist: down ? nil : (ist * 10).rounded() / 10, valves: valves))
        }
        return FRoom(
            id: setup.id, placeId: setup.placeId, name: setup.name, short: setup.short,
            radiators: setup.radiators, istSource: setup.istSource, samples: samples, events: events(setup)
        )
    }

    private static func events(_ setup: Setup) -> [FEvent] {
        var events: [FEvent] = []
        for day in days {
            for point in setup.plan {
                let date = d(day, point.0)
                guard date > weekStart, date <= now else { continue }
                events.append(FEvent(kind: .plan, date: date, title: "Plan \(point.2): Soll \(Fmt.temp(point.1))", reason: "plan"))
            }
        }
        for interval in setup.windowOpen {
            let isOpen = interval.end >= now
            events.append(FEvent(
                kind: .window, date: interval.start, end: interval.end,
                title: "\(setup.window ?? "Fenster") offen → Modus Aus" + (isOpen ? ", noch offen" : ", zu um \(Fmt.time(interval.end))"),
                reason: "fenster"
            ))
        }
        for interval in setup.fireplace {
            let isOn = interval.end >= now
            events.append(FEvent(
                kind: .fireplace, date: interval.start, end: interval.end,
                title: "Kamin an → Modus Aus" + (isOn ? ", automatisches Ende 03:30" : ", aus um \(Fmt.time(interval.end))"),
                reason: "kamin"
            ))
        }
        for manual in setup.manual {
            let plan = planSoll(setup, at: manual.0).0
            events.append(FEvent(
                kind: .observed, date: manual.0,
                title: "Soll am Gerät \(Fmt.temp(plan)) → \(Fmt.temp(manual.2)), weicht vom zuletzt geschriebenen ab",
                reason: "beobachtet"
            ))
        }
        events += setup.extraEvents + globalEvents
        return events.sorted { $0.date < $1.date }
    }

    static let rooms: [FRoom] = setups.map { build($0) }

    /// Coldest first; a room without Ist goes last.
    static let sortedRooms: [FRoom] = rooms.sorted { ($0.delta ?? .infinity) < ($1.delta ?? .infinity) }

    static func room(_ id: String) -> FRoom { rooms.first { $0.id == id }! }

    static let heatmap: [FCell] = rooms.flatMap { room in
        heatmapDays.flatMap { day in
            (0..<4).map { segment in
                let start = day.addingTimeInterval(Double(segment) * 6 * 3_600)
                let end = start.addingTimeInterval(6 * 3_600)
                let inSegment = room.samples.filter { $0.date >= start && $0.date < end }
                let deltas = inSegment.compactMap(\.delta)
                let mostlyMissing = inSegment.isEmpty || deltas.count * 2 < inSegment.count
                return FCell(
                    roomID: room.id, day: day, segment: segment,
                    delta: mostlyMissing ? nil : deltas.reduce(0, +) / Double(deltas.count)
                )
            }
        }
    }
}

//
//  HeatingPreviewData.swift
//  ControllerFeatures
//
//  Seed data of the Heizung previews, ported from the design prototype's mock model. It has the
//  shape of the room endpoint's response.
//

import Foundation
import HAModels

enum HeatingPreviewData {
    struct Room: Identifiable {
        let id: String
        let radiators: [String]
        /// Δ at "now"; `nil`: the room has no actual value (and had none since `lastIst`).
        let delta: Double?
        /// A daily heat-up after the morning plan switch, so the gap shows orange and blue.
        var bursts = false
        /// Events of the last seven days; `detail` keeps those inside the range, like the server.
        var events: [HeatingEvent] = []

        /// The grid of this room for `range`, ending at `HeatingPreviewData.now`.
        func detail(_ range: HeatingRange) -> HeatingRoomDetail {
            let end = HeatingPreviewData.now
            let start = end.addingTimeInterval(-range.duration)
            let samples = stride(from: start, through: end, by: range.step).map { date in
                sample(at: date)
            }
            return HeatingRoomDetail(placeId: id, name: id, range: range, istSource: .thermostats(radiators), radiators: radiators, samples: samples,
                                     lastIst: delta == nil ? HeatingPreviewData.lastIstOfSilentRoom : end,
                                     events: clipped(events, to: start...end))
        }

        /// Drops what lies outside the range and pins what began before it at the range start.
        private func clipped(_ events: [HeatingEvent], to range: ClosedRange<Date>) -> [HeatingEvent] {
            events.filter { ($0.end ?? $0.start) >= range.lowerBound && $0.start <= range.upperBound }
                .map { HeatingEvent(source: $0.source, title: $0.title, reason: $0.reason, start: $0.start, end: $0.end, pin: max($0.start, range.lowerBound)) }
                .sorted { $0.pin < $1.pin }
        }

        private func sample(at date: Date) -> HeatingSample {
            let plan = HeatingPreviewData.plan(at: date)
            guard let delta else {
                return HeatingSample(date: date, ist: nil, sollPlan: plan, valves: radiators.map { _ in nil })
            }
            let hours = date.timeIntervalSince1970 / 3_600
            let calendar = HeatingPreviewData.calendar
            let hourOfDay = calendar.component(.hour, from: date)
            let isSilent = (2..<5).contains(hourOfDay) && calendar.component(.day, from: date).isMultiple(of: 2)
            // The wobble fades out towards now, so Δ at the end is exactly `delta`.
            let settled = min(HeatingPreviewData.now.timeIntervalSince(date) / 3_600, 1)
            var offset = delta + settled * 0.3 * sin(hours / 2.2)
            if bursts {
                let minutes = Double(hourOfDay * 60 + calendar.component(.minute, from: date)) - 6.5 * 60
                offset += settled * (minutes >= 0 ? 2.8 * exp(-minutes / 90) - 0.2 : -0.9)
            }
            let ist = isSilent ? nil : ((plan + offset) * 10).rounded() / 10
            let valves = radiators.indices.map { index -> Double? in
                guard !isSilent else { return nil }
                let demand = (plan - (ist ?? plan)) * 18 + 10 - Double(index) * 8
                return min(max(demand, 0), 100).rounded()
            }
            return HeatingSample(date: date, ist: ist, sollPlan: plan, valves: valves)
        }
    }

    static let calendar = HeatingOverviewBuilder.berlin

    /// 15.11.2026 22:40, the fixed "now" of the previews.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 22, minute: 40))!

    /// The Δ of the design's mock: Bad OG far below plan (runs off the end), Schlafzimmer at plan (a grey pill),
    /// Esszimmer warm, Kaminzimmer without an actual value.
    static let rooms: [Room] = [
        Room(id: "Bad OG", radiators: ["Eve Thermo"], delta: -3.7),
        Room(id: "Küche", radiators: ["Eve Thermo links", "Eve Thermo rechts"], delta: -1.0, events: kitchenEvents),
        Room(id: "Schlafzimmer", radiators: ["Eve Thermo"], delta: 0.2, bursts: true, events: bedroomEvents),
        Room(id: "Arbeitszimmer", radiators: ["Eve Thermo"], delta: 0.8),
        Room(id: "Esszimmer", radiators: ["Eve Thermo"], delta: 2.1),
        Room(id: "Kaminzimmer", radiators: ["Eve Thermo"], delta: nil)
    ]

    /// A moment of the last days: `day` of November 2026, `hour:minute` local.
    static func moment(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private static func event(_ source: HeatingEventSource, _ title: String, _ reason: String, _ start: Date, until end: Date? = nil) -> HeatingEvent {
        HeatingEvent(source: source, title: title, reason: reason, start: start, end: end)
    }

    /// Every source, a window and a fireplace area, and a crowd of four events around 13 o'clock that folds into "+3".
    static let kitchenEvents: [HeatingEvent] = [
        event(.plan, "Plan 17,5 °C", "Planwechsel: Eve Thermo links, Eve Thermo rechts auf 17,5 °C gesetzt.", moment(14, 23)),
        event(.plan, "Plan 21,0 °C", "Planwechsel: Eve Thermo links, Eve Thermo rechts auf 21,0 °C gesetzt.", moment(15, 6)),
        event(.observed, "Von Hand: 23,0 °C", "Eve Thermo links steht auf 23,0 °C statt 21,0 °C, dem Wert, den der Server zuletzt geschrieben hat. Der Server greift nicht ein.", moment(15, 8, 10)),
        event(.window, "Fenster offen", "Fenster „Küche Fenster“ war 25 min offen, die Heizkörper waren aus.", moment(15, 9, 30), until: moment(15, 9, 55)),
        event(.plan, "Plan 21,0 °C", "Planwechsel: Eve Thermo links, Eve Thermo rechts auf 21,0 °C gesetzt.", moment(15, 12, 55)),
        event(.system, "System", "Der Server hat Eve Thermo links, Eve Thermo rechts auf 21,0 °C gesetzt (Deploy oder Zeitablauf).", moment(15, 13, 0)),
        event(.observed, "Von Hand: 19,0 °C", "Eve Thermo rechts steht auf 19,0 °C statt 21,0 °C. Der Server greift nicht ein.", moment(15, 13, 5)),
        event(.observed, "Von Hand: 21,0 °C", "Eve Thermo links steht wieder auf 21,0 °C.", moment(15, 13, 8)),
        event(.fireplace, "Kamin an", "Kamin war 3 h an: die Heizkörper waren aus.", moment(15, 17, 30), until: moment(15, 20, 30))
    ]

    static let bedroomEvents: [HeatingEvent] = [
        event(.window, "Fenster offen", "Fenster „Schlafzimmer Fenster“ war 40 min offen, die Heizkörper waren aus.", moment(13, 7), until: moment(13, 7, 40)),
        event(.observed, "Von Hand: 22,0 °C", "Eve Thermo steht auf 22,0 °C statt 17,5 °C. Der Server greift nicht ein.", moment(14, 21)),
        event(.fireplace, "Kamin an", "Der Kamin wurde nach 8 h 0 min per Zeitablauf ausgeschaltet; dazu kam die Benachrichtigung „Kamin aus“.", moment(14, 12), until: moment(14, 20))
    ]

    /// 10.11.2026 14:40: the last actual value of the room without data.
    static let lastIstOfSilentRoom = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 14, minute: 40))!

    /// The plan target: 21 ° from 6 to 23 o'clock, 17,5 ° at night.
    static func plan(at date: Date) -> Double {
        (6..<23).contains(calendar.component(.hour, from: date)) ? 21 : 17.5
    }

    private static let shortNames = ["Schlafzimmer": "Schlaf", "Arbeitszimmer": "Arbeit", "Esszimmer": "Essen", "Kaminzimmer": "Kamin"]

    /// The rooms of the overview endpoint's response, as the server would sort them (any order).
    static var overviewRooms: [HeatingOverviewRoom] { overviewRooms(following: []) }

    /// The overview rooms, those named in `following` follow the fireplace.
    static func overviewRooms(following: Set<String>) -> [HeatingOverviewRoom] {
        rooms.map { room in
            let latest = room.detail(.twoHours).latest
            return HeatingOverviewRoom(placeId: room.id, name: room.id, shortName: shortNames[room.id] ?? room.id, ist: latest?.ist, sollPlan: latest?.sollPlan,
                                       istSource: .thermostats(room.radiators), followsFireplace: following.contains(room.id))
        }
    }

    /// The heatmap cells of the overview endpoint: mean Δ per room, local day and six-hour segment of the last seven days.
    static var heatmap: [HeatingHeatmapCell] {
        rooms.flatMap { HeatingOverviewBuilder.heatmap(for: $0.detail(.week), calendar: calendar) }
    }

    /// The rooms that follow the fireplace in the fireplace previews.
    static let fireplaceRooms: Set<String> = ["Küche", "Kaminzimmer"]

    /// A store state with the fireplace rooms marked; the fireplace burns since two hours (ends in six).
    static func fireplaceState(on isOn: Bool, selected placeId: String? = nil) -> HeatingFeature.State {
        var state = state(placeId)
        state.rooms = HeatingFeature.sorted(overviewRooms(following: fireplaceRooms))
        state.fireplace = isOn ? FireplaceState(isOn: true, since: now.addingTimeInterval(-2 * 3_600)) : .off
        return state
    }

    /// A store state with the overview loaded and `selected` open (none: only the overview).
    static func state(_ placeId: String? = nil, range: HeatingRange = .day) -> HeatingFeature.State {
        var state = HeatingFeature.State()
        state.rooms = HeatingFeature.sorted(overviewRooms)
        state.updatedAt = now
        state.heatmap = heatmap
        state.selectedPlaceId = placeId
        state.range = range
        state.detail = placeId.flatMap { id in rooms.first { $0.id == id }?.detail(range) }
        return state
    }
}

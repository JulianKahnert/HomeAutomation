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

        /// The grid of this room for `range`, ending at `HeatingPreviewData.now`.
        func detail(_ range: HeatingRange) -> HeatingRoomDetail {
            let end = HeatingPreviewData.now
            let start = end.addingTimeInterval(-range.duration)
            let samples = stride(from: start, through: end, by: range.step).map { date in
                sample(at: date)
            }
            return HeatingRoomDetail(placeId: id, name: id, range: range, istSource: .thermostats(radiators), radiators: radiators, samples: samples,
                                     lastIst: delta == nil ? HeatingPreviewData.lastIstOfSilentRoom : end)
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

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    /// 15.11.2026 22:40, the fixed "now" of the previews.
    static let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 22, minute: 40))!

    /// The Δ of the design's mock: Bad OG far below plan (runs off the end), Schlafzimmer at plan (a grey pill),
    /// Esszimmer warm, Kaminzimmer without an actual value.
    static let rooms: [Room] = [
        Room(id: "Bad OG", radiators: ["Eve Thermo"], delta: -3.7),
        Room(id: "Küche", radiators: ["Eve Thermo links", "Eve Thermo rechts"], delta: -1.0),
        Room(id: "Schlafzimmer", radiators: ["Eve Thermo"], delta: 0.2, bursts: true),
        Room(id: "Arbeitszimmer", radiators: ["Eve Thermo"], delta: 0.8),
        Room(id: "Esszimmer", radiators: ["Eve Thermo"], delta: 2.1),
        Room(id: "Kaminzimmer", radiators: ["Eve Thermo"], delta: nil)
    ]

    /// 10.11.2026 14:40: the last actual value of the room without data.
    static let lastIstOfSilentRoom = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 14, minute: 40))!

    /// The plan target: 21 ° from 6 to 23 o'clock, 17,5 ° at night.
    static func plan(at date: Date) -> Double {
        (6..<23).contains(calendar.component(.hour, from: date)) ? 21 : 17.5
    }

    private static let shortNames = ["Schlafzimmer": "Schlaf", "Arbeitszimmer": "Arbeit", "Esszimmer": "Essen", "Kaminzimmer": "Kamin"]

    /// The rooms of the overview endpoint's response, as the server would sort them (any order).
    static var overviewRooms: [HeatingOverviewRoom] {
        rooms.map { room in
            let latest = room.detail(.twoHours).latest
            return HeatingOverviewRoom(placeId: room.id, name: room.id, shortName: shortNames[room.id] ?? room.id, ist: latest?.ist, sollPlan: latest?.sollPlan,
                                       istSource: .thermostats(room.radiators))
        }
    }

    /// The heatmap cells of the overview endpoint: mean Δ per room, local day and six-hour segment of the last seven days.
    static var heatmap: [HeatingHeatmapCell] {
        rooms.flatMap { HeatingOverviewBuilder.heatmap(for: $0.detail(.week), calendar: calendar) }
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

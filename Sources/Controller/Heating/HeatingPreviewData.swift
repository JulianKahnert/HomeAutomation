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
        enum Kind { case normal, cold, warm, noData }

        let id: String
        let radiators: [String]
        let kind: Kind

        /// The grid of this room for `range`, ending at `HeatingPreviewData.now`.
        func detail(_ range: HeatingRange) -> HeatingRoomDetail {
            let end = HeatingPreviewData.now
            let start = end.addingTimeInterval(-range.duration)
            let samples = stride(from: start, through: end, by: range.step).map { date in
                sample(at: date)
            }
            return HeatingRoomDetail(placeId: id, name: id, range: range, istSource: .thermostats(radiators), radiators: radiators, samples: samples)
        }

        private func sample(at date: Date) -> HeatingSample {
            let plan = HeatingPreviewData.plan(at: date)
            if kind == .noData {
                return HeatingSample(date: date, ist: nil, sollPlan: plan, valves: radiators.map { _ in nil })
            }
            let hours = date.timeIntervalSince1970 / 3_600
            let hourOfDay = HeatingPreviewData.calendar.component(.hour, from: date)
            let isSilent = (2..<5).contains(hourOfDay) && HeatingPreviewData.calendar.component(.day, from: date).isMultiple(of: 2)
            let offset: Double = switch kind {
            case .cold: -1.6 + 0.9 * sin(hours / 3)
            case .warm: 1.3 + 0.4 * sin(hours / 3)
            default: 0.35 * sin(hours / 2.2) + 0.15
            }
            let ist = isSilent ? nil : ((plan + offset) * 10).rounded() / 10
            let valves = radiators.indices.map { index -> Double? in
                guard !isSilent else { return nil }
                let demand = (plan - (ist ?? plan)) * 45 + 20 - Double(index) * 8
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

    static let rooms: [Room] = [
        Room(id: "Bad OG", radiators: ["Eve Thermo"], kind: .cold),
        Room(id: "Küche", radiators: ["Eve Thermo links", "Eve Thermo rechts"], kind: .normal),
        Room(id: "Kaminzimmer", radiators: ["Eve Thermo"], kind: .noData),
        Room(id: "Schlafzimmer", radiators: ["Eve Thermo"], kind: .warm),
        Room(id: "Flur", radiators: ["Eve Thermo"], kind: .normal)
    ]

    /// The plan target: 21 ° from 6 to 22 o'clock, 17,5 ° at night.
    static func plan(at date: Date) -> Double {
        (6..<22).contains(calendar.component(.hour, from: date)) ? 21 : 17.5
    }

    /// The rooms of the overview endpoint's response, as the server would sort them (any order).
    static var overviewRooms: [HeatingOverviewRoom] {
        rooms.map { room in
            let latest = room.detail(.twoHours).latest
            return HeatingOverviewRoom(placeId: room.id, name: room.id, shortName: room.id, ist: latest?.ist, sollPlan: latest?.sollPlan,
                                       istSource: .thermostats(room.radiators))
        }
    }

    /// A store state with the overview loaded and `selected` open (none: only the overview).
    static func state(selected placeId: String?, range: HeatingRange = .day) -> HeatingFeature.State {
        var state = HeatingFeature.State()
        state.rooms = HeatingFeature.sorted(overviewRooms)
        state.selectedPlaceId = placeId
        state.range = range
        state.detail = placeId.flatMap { id in rooms.first { $0.id == id }?.detail(range) }
        return state
    }
}

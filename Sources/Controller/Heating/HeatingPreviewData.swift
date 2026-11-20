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
        enum Kind { case normal, cold, noData }

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
            let offset = kind == .cold ? -1.6 + 0.9 * sin(hours / 3) : 0.35 * sin(hours / 2.2) + 0.15
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
        Room(id: "Kaminzimmer", radiators: ["Eve Thermo"], kind: .noData)
    ]

    /// The plan target: 21 ° from 6 to 22 o'clock, 17,5 ° at night.
    static func plan(at date: Date) -> Double {
        (6..<22).contains(calendar.component(.hour, from: date)) ? 21 : 17.5
    }

    static var heatingRooms: [HeatingFeature.Room] {
        rooms.map { HeatingFeature.Room(placeId: $0.id, name: $0.id) }
    }

    /// A store state with `placeId` selected and its detail loaded.
    static func state(_ placeId: String = "Bad OG", range: HeatingRange = .day) -> HeatingFeature.State {
        var state = HeatingFeature.State()
        state.rooms = heatingRooms
        state.selectedPlaceId = placeId
        state.range = range
        state.detail = rooms.first { $0.id == placeId }?.detail(range)
        return state
    }
}

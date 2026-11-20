//
//  HeatingOverview.swift
//  HAModels
//

import Foundation

/// Where a room's Δ lies relative to the comfort band (glossary: Δ).
public enum HeatingComfort: Sendable, Codable, Equatable {
    case tooCold, ok, tooWarm

    /// Comfort band of ±0.5 K; the edges belong to the band.
    public static let band = 0.5

    public init(delta: Double) {
        if delta < -Self.band {
            self = .tooCold
        } else if delta > Self.band {
            self = .tooWarm
        } else {
            self = .ok
        }
    }
}

/// One room of the overview: actual, plan target, Δ and where the actual value comes from.
public struct HeatingOverviewRoom: Sendable, Codable, Equatable, Identifiable {
    public let placeId: String
    public let name: String
    /// The label under the bar.
    public let shortName: String
    /// Actual value now; `nil` while there is none.
    public let ist: Double?
    /// Plan target now; `nil` when unknown.
    public let sollPlan: Double?
    public let istSource: HeatingIstSource
    /// Whether the room follows the fireplace: it shows the flame and the orange area while it burns.
    public let followsFireplace: Bool

    public var id: String { placeId }

    /// Actual minus plan target; `nil` when one of them is missing.
    public var delta: Double? {
        guard let ist, let sollPlan else { return nil }
        return ist - sollPlan
    }

    /// `nil` when the room has no Δ.
    public var comfort: HeatingComfort? { delta.map(HeatingComfort.init(delta:)) }

    public init(placeId: String, name: String, shortName: String, ist: Double?, sollPlan: Double?, istSource: HeatingIstSource, followsFireplace: Bool = false) {
        self.placeId = placeId
        self.name = name
        self.shortName = shortName
        self.ist = ist
        self.sollPlan = sollPlan
        self.istSource = istSource
        self.followsFireplace = followsFireplace
    }
}

/// One cell of the week heatmap: the mean Δ of one room over one six-hour segment of a local day.
public struct HeatingHeatmapCell: Sendable, Codable, Equatable {
    public let placeId: String
    /// Start of the local day (Europe/Berlin).
    public let day: Date
    /// 0 = 0-6, 1 = 6-12, 2 = 12-18, 3 = 18-24 o'clock local time.
    public let segment: Int
    /// Mean Δ; `nil` when more than half of the segment has no actual value.
    public let delta: Double?

    public init(placeId: String, day: Date, segment: Int, delta: Double?) {
        self.placeId = placeId
        self.day = day
        self.segment = segment
        self.delta = delta
    }
}

/// What the overview endpoint answers.
public struct HeatingOverview: Sendable, Codable, Equatable {
    public let rooms: [HeatingOverviewRoom]
    /// Room × day × segment for the last seven local days, today included.
    public let heatmap: [HeatingHeatmapCell]

    public init(rooms: [HeatingOverviewRoom], heatmap: [HeatingHeatmapCell] = []) {
        self.rooms = rooms
        self.heatmap = heatmap
    }
}

/// Builds the overview from the newest sample of each room's detail grid, so actual and plan target
/// follow the very same rules as the detail.
public struct HeatingOverviewBuilder: Sendable {
    private let detail: HeatingRoomDetailBuilder
    private let calendar: Calendar

    /// - Parameter calendar: Decides the local days and segment boundaries; Europe/Berlin by default.
    public init(detail: HeatingRoomDetailBuilder, calendar: Calendar = HeatingOverviewBuilder.berlin) {
        self.detail = detail
        self.calendar = calendar
    }

    public static let berlin: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }()

    public func overview(for rooms: [HeatingRoomSources]) async throws -> HeatingOverview {
        var result: [HeatingOverviewRoom] = []
        var cells: [HeatingHeatmapCell] = []
        for room in rooms {
            let week = try await detail.detail(for: room, range: .week)
            cells += Self.heatmap(for: week, calendar: calendar)
            let grid = HeatingRoomDetail(placeId: week.placeId, name: week.name, range: .twoHours, istSource: week.istSource,
                                         radiators: week.radiators, samples: Array(week.samples.suffix(1)))
            result.append(HeatingOverviewRoom(placeId: room.placeId,
                                              name: room.name,
                                              shortName: Self.shortName(room.name),
                                              ist: grid.latest?.ist,
                                              sollPlan: grid.latest?.sollPlan,
                                              istSource: grid.istSource,
                                              followsFireplace: room.followsFireplace))
        }
        return HeatingOverview(rooms: result, heatmap: cells)
    }

    /// Buckets the week grid by local day and six-hour segment. Bucketing by the local clock keeps the
    /// segments right on days with 23 or 25 hours.
    public static func heatmap(for week: HeatingRoomDetail, calendar: Calendar = berlin) -> [HeatingHeatmapCell] {
        guard let last = week.end else { return [] }
        let firstDay = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: last)) ?? last
        var buckets: [Date: [Int: [HeatingSample]]] = [:]
        for sample in week.samples where sample.date >= firstDay {
            let day = calendar.startOfDay(for: sample.date)
            let segment = calendar.component(.hour, from: sample.date) / 6
            buckets[day, default: [:]][segment, default: []].append(sample)
        }
        return buckets.keys.sorted().flatMap { day in
            (0..<4).compactMap { segment -> HeatingHeatmapCell? in
                guard let samples = buckets[day]?[segment] else { return nil }
                let deltas = samples.compactMap(\.delta)
                let isMostlyMissing = (samples.count - deltas.count) * 2 > samples.count
                let mean = isMostlyMissing || deltas.isEmpty ? nil : deltas.reduce(0, +) / Double(deltas.count)
                return HeatingHeatmapCell(placeId: week.placeId, day: day, segment: segment, delta: mean)
            }
        }
    }

    static func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: " - ", with: " ")
    }
}

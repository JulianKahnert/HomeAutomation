//
//  HeatingRoomDetail.swift
//  HAModels
//

import Foundation

/// The time range of the room detail in the Heizung tab. The raw value is the query value of the endpoint.
public enum HeatingRange: String, Sendable, Codable, CaseIterable, Equatable {
    case twoHours = "2h"
    case day = "24h"
    case week = "7d"

    public var duration: TimeInterval {
        switch self {
        case .twoHours: return 2 * 3_600
        case .day: return 24 * 3_600
        case .week: return 7 * 24 * 3_600
        }
    }

    /// The distance of two samples: 5 minutes, 30 minutes for 7 days.
    public var step: TimeInterval {
        self == .week ? 30 * 60 : 5 * 60
    }
}

/// Where the actual value of a room comes from (glossary: actual).
public enum HeatingIstSource: Sendable, Codable, Equatable {
    case roomSensor(String)
    case thermostats([String])
}

/// One point of the time grid of a room.
public struct HeatingSample: Sendable, Codable, Equatable {
    public let date: Date
    /// Actual value; `nil` while there is none.
    public let ist: Double?
    /// Plan target; `nil` when unknown.
    public let sollPlan: Double?
    /// Valve opening in percent per radiator, in the order of `HeatingRoomDetail.radiators`; `nil` while silent.
    public let valves: [Double?]

    /// Actual minus plan target (glossary: Δ); `nil` when one of them is missing.
    public var delta: Double? {
        guard let ist, let sollPlan else { return nil }
        return ist - sollPlan
    }

    public init(date: Date, ist: Double?, sollPlan: Double?, valves: [Double?]) {
        self.date = date
        self.ist = ist
        self.sollPlan = sollPlan
        self.valves = valves
    }
}

/// What the room endpoint answers: the grid of a room for one range.
public struct HeatingRoomDetail: Sendable, Codable, Equatable {
    public let placeId: String
    public let name: String
    public let range: HeatingRange
    public let istSource: HeatingIstSource
    /// Radiator names in a stable order; `HeatingSample.valves` follows it.
    public let radiators: [String]
    public let samples: [HeatingSample]
    /// When the room last had an actual value, also before the range; `nil` when it never had one.
    public let lastIst: Date?
    /// What happened in the range, sorted by pin position (glossary: heating event).
    public let events: [HeatingEvent]

    public init(placeId: String, name: String, range: HeatingRange, istSource: HeatingIstSource, radiators: [String], samples: [HeatingSample],
                lastIst: Date? = nil, events: [HeatingEvent] = []) {
        self.events = events
        self.placeId = placeId
        self.name = name
        self.range = range
        self.istSource = istSource
        self.radiators = radiators
        self.samples = samples
        self.lastIst = lastIst
    }

    public var start: Date? { samples.first?.date }
    public var end: Date? { samples.last?.date }
    /// The newest sample; the header of the detail shows its values.
    public var latest: HeatingSample? { samples.last }
    /// `true` when no sample has an actual value ("Keine Daten im Zeitraum").
    public var hasNoData: Bool { samples.allSatisfy { $0.ist == nil } }
    /// `true` when any radiator reported a valve value in the range.
    public var hasValues: Bool { samples.contains { $0.valves.contains { $0 != nil } } }
}

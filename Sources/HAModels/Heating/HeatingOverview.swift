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

/// What the overview endpoint answers.
public struct HeatingOverview: Sendable, Codable, Equatable {
    public let rooms: [HeatingOverviewRoom]

    public init(rooms: [HeatingOverviewRoom]) {
        self.rooms = rooms
    }
}

/// Builds the overview from the newest sample of each room's detail grid, so actual and plan target
/// follow the very same rules as the detail.
public struct HeatingOverviewBuilder: Sendable {
    private let detail: HeatingRoomDetailBuilder

    public init(detail: HeatingRoomDetailBuilder) {
        self.detail = detail
    }

    public func overview(for rooms: [HeatingRoomSources]) async throws -> HeatingOverview {
        var result: [HeatingOverviewRoom] = []
        for room in rooms {
            let grid = try await detail.detail(for: room, range: .twoHours)
            result.append(HeatingOverviewRoom(placeId: room.placeId,
                                              name: room.name,
                                              shortName: Self.shortName(room.name),
                                              ist: grid.latest?.ist,
                                              sollPlan: grid.latest?.sollPlan,
                                              istSource: grid.istSource,
                                              followsFireplace: room.followsFireplace))
        }
        return HeatingOverview(rooms: result)
    }

    static func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: " - ", with: " ")
    }
}

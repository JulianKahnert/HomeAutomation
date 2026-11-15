//
//  WindowOpenContentState.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 06.03.25.
//

import Foundation

/// The Live Activity data format for offene Fenster (ContentState v2).
///
/// The server fills and sorts it; the widget renders it as it is and never re-sorts.
public struct WindowContentState: Hashable, Sendable {
    /// The name used in APNS `attributes-type` field for push-to-start Live Activities.
    ///
    /// IMPORTANT: This value MUST exactly match the name of the `ActivityAttributes` struct
    /// used in the iOS app (defined in `Sources/Controller/LiveActivity/WindowAttributes.swift`).
    /// The iOS app registers Live Activities with `Activity<WindowAttributes>`, so Apple's APNS
    /// uses this string to identify which ActivityAttributes implementation should handle the
    /// push notification. If the names don't match, the push notification will be silently ignored.
    public static let activityTypeName = "WindowAttributes"

    /// The server sends at most this many windows to stay well below the 4 KB payload limit.
    /// ``openCount`` and ``overdueCount`` always count every offene Fenster.
    public static let maxWindowCount = 20

    /// The offenen Fenster: überschritten first, then by Fensterschließzeit, window name as tiebreak.
    public let windows: [Window]
    /// The number of all offenen Fenster, including those cut off by ``maxWindowCount``.
    public let openCount: Int
    /// The number of all überschrittenen Fenster, including those cut off by ``maxWindowCount``.
    public let overdueCount: Int
    /// The latest stored outdoor temperature reading in °C; `nil` without a reading.
    public let outdoorTemperature: Double?
    /// When the Live Activity goes stale: the earliest Fensterschließzeit among all windows not yet
    /// überschritten, including those cut off by ``maxWindowCount``. `nil` when every window is überschritten.
    public let staleDate: Date?

    public init(windows: [Window], openCount: Int, overdueCount: Int, outdoorTemperature: Double? = nil, staleDate: Date? = nil) {
        self.windows = windows
        self.openCount = openCount
        self.overdueCount = overdueCount
        self.outdoorTemperature = outdoorTemperature
        self.staleDate = staleDate
    }

    /// Caps `sortedWindows` at ``maxWindowCount`` and derives the counts and the stale date from all of them.
    /// - Parameter sortedWindows: Every offene Fenster, already in Live Activity order.
    public init(sortedWindows: [Window], outdoorTemperature: Double? = nil) {
        self.init(windows: Array(sortedWindows.prefix(Self.maxWindowCount)),
                  openCount: sortedWindows.count,
                  overdueCount: sortedWindows.filter(\.isOverdue).count,
                  outdoorTemperature: outdoorTemperature,
                  staleDate: sortedWindows.filter { !$0.isOverdue }.map(\.closeBy).min())
    }

    /// No offenen Fenster.
    public static let empty = WindowContentState(windows: [], openCount: 0, overdueCount: 0)
}

extension WindowContentState: Codable {
    private enum CodingKeys: String, CodingKey {
        case windows, openCount, overdueCount, outdoorTemperature, staleDate
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windows = try container.decode([Window].self, forKey: .windows)
        openCount = try container.decode(Int.self, forKey: .openCount)
        overdueCount = try container.decode(Int.self, forKey: .overdueCount)
        outdoorTemperature = try container.decodeIfPresent(Double.self, forKey: .outdoorTemperature)
        staleDate = try container.decodeIfPresent(String.self, forKey: .staleDate).map { try Date($0, strategy: .iso8601) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(windows, forKey: .windows)
        try container.encode(openCount, forKey: .openCount)
        try container.encode(overdueCount, forKey: .overdueCount)
        try container.encodeIfPresent(outdoorTemperature, forKey: .outdoorTemperature)
        try container.encodeIfPresent(staleDate?.ISO8601Format(), forKey: .staleDate)
    }
}

extension WindowContentState: Identifiable {
    public var id: Int {
        hashValue
    }
}

extension WindowContentState {
    public struct Window: Hashable, Sendable, Identifiable {
        /// Stable across updates, derived from the window's entity.
        public let id: String
        /// The window name without the room.
        public let name: String
        /// The Raum the window is in.
        public let room: String
        public let opened: Date
        /// The Fensterschließzeit: opened + Lüftungslimit.
        public let closeBy: Date
        /// Set by the server once the Fensterschließzeit has passed.
        public let isOverdue: Bool

        public init(id: String, name: String, room: String, opened: Date, closeBy: Date, isOverdue: Bool) {
            self.id = id
            self.name = name
            self.room = room
            self.opened = opened
            self.closeBy = closeBy
            self.isOverdue = isOverdue
        }

        /// The id of the window `name` in `room`, the same for every update.
        public static func id(room: String, name: String) -> String {
            "window-\(room)-\(name)"
        }
    }
}

extension WindowContentState.Window: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, room, opened, closeBy, isOverdue
    }

    // Dates travel as ISO 8601 strings, so the APNS payload decodes the same in ActivityKit
    // whatever date strategy the server's encoder uses.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        room = try container.decode(String.self, forKey: .room)
        opened = try Self.decodeDate(forKey: .opened, in: container)
        closeBy = try Self.decodeDate(forKey: .closeBy, in: container)
        isOverdue = try container.decode(Bool.self, forKey: .isOverdue)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(room, forKey: .room)
        try container.encode(opened.ISO8601Format(), forKey: .opened)
        try container.encode(closeBy.ISO8601Format(), forKey: .closeBy)
        try container.encode(isOverdue, forKey: .isOverdue)
    }

    private static func decodeDate(forKey key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>) throws -> Date {
        let string = try container.decode(String.self, forKey: key)
        do {
            return try Date(string, strategy: .iso8601)
        } catch {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Invalid ISO 8601 date: \(string)")
        }
    }
}

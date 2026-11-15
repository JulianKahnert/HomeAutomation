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
public struct WindowContentState: Codable, Hashable, Sendable {
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

    public init(windows: [Window], openCount: Int, overdueCount: Int, outdoorTemperature: Double? = nil) {
        self.windows = windows
        self.openCount = openCount
        self.overdueCount = overdueCount
        self.outdoorTemperature = outdoorTemperature
    }

    /// No offenen Fenster.
    public static let empty = WindowContentState(windows: [], openCount: 0, overdueCount: 0)

    /// When the Live Activity goes stale: the earliest Fensterschließzeit among windows not yet
    /// überschritten, so the widget shows "überschritten?" if the update marking it is lost.
    /// `nil` when every window is überschritten.
    public var staleDate: Date? {
        windows.filter { !$0.isOverdue }.map(\.closeBy).min()
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

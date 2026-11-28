//
//  Origin.swift
//  HAModels
//

import Foundation

/// Where a change of a state came from: `homekit`, `server` or the name of a polling job.
///
/// Only a change with origin `homekit` counts as a sign of life for HomeKit, so a polled value
/// cannot hide a HomeKit outage.
public struct Origin: RawRepresentable, Hashable, Sendable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String

    /// A report that came in over the adapter link from HomeKit.
    public static let homekit = Origin(rawValue: "homekit")
    /// A state the server holds itself.
    public static let server = Origin(rawValue: "server")

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    /// A state the app set through the general route (T18); the server checked and stored it like a server report.
    public static let app = Origin(rawValue: "app")

    /// The origin of a polling job; the job's name is the origin.
    public static func job(_ name: String) -> Origin {
        Origin(rawValue: name)
    }

    public var description: String { rawValue }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

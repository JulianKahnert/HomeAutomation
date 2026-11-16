//
//  LiveActivityOptions.swift
//  HomeAutomation
//

import Foundation

/// How a Live Activity start or update push is delivered.
public struct LiveActivityOptions: Equatable, Sendable {
    /// A Live Activity alert: it expands the Dynamic Island and plays a sound.
    public struct Alert: Equatable, Sendable {
        public let title: String
        public let body: String

        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    /// The APNS push priority.
    public enum Priority: Int, Equatable, Sendable {
        /// Priority 5: delivered when convenient for the device's power; does not count against the APNS budget.
        case low = 5
        /// Priority 10: delivered immediately; counts against the APNS budget.
        case high = 10
    }

    public let alert: Alert?
    /// From this date on the system marks the activity stale.
    public let staleDate: Date?
    public let priority: Priority

    public init(alert: Alert? = nil, staleDate: Date? = nil, priority: Priority) {
        self.alert = alert
        self.staleDate = staleDate
        self.priority = priority
    }
}

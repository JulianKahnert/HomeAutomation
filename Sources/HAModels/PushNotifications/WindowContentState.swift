//
//  WindowOpenContentState.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 06.03.25.
//

import Foundation

public struct WindowContentState: Codable, Hashable, Sendable {
    public let windowStates: [WindowState]

    public init(windowStates: [WindowState]) {
        self.windowStates = windowStates
    }
}

extension WindowContentState: Identifiable {
    public struct WindowState: Codable, Hashable, Sendable {
        public let name: String
        public let openedIsoTimeStamp: String
        public let maxOpenDuration: Double

        public var opened: Date {
            return ISO8601DateFormatter().date(from: openedIsoTimeStamp)!
        }

        public var end: Date {
            opened.addingTimeInterval(maxOpenDuration)
        }

        public init(name: String, opened: Date, maxOpenDuration: TimeInterval) {
            self.name = name
            self.openedIsoTimeStamp = opened.ISO8601Format()
            self.maxOpenDuration = maxOpenDuration
        }
    }

    public var id: Int {
        hashValue
    }
}

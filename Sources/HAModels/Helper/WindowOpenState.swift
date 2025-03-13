//
//  WindowOpenState.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 13.03.25.
//

import Foundation

public struct WindowOpenState: Hashable, Encodable, Sendable {
    public let name: String
    public let opened: Date
    public let maxOpenDuration: TimeInterval

    public init(name: String, opened: Date, maxOpenDuration: TimeInterval) {
        self.name = name
        self.opened = opened
        self.maxOpenDuration = maxOpenDuration
    }
}

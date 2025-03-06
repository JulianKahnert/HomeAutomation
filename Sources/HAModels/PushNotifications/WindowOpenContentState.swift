//
//  WindowOpenContentState.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 06.03.25.
//

import Foundation

public struct WindowOpenContentState: Codable, Hashable, Sendable {
    public struct WindowState: Codable, Hashable, Sendable {
        public let name: String
        public let opened: Date
        public let maxOpenDuration: TimeInterval
        
        public init(name: String, opened: Date, maxOpenDuration: TimeInterval) {
            self.name = name
            self.opened = opened
            self.maxOpenDuration = maxOpenDuration
        }
    }
    
    public let windowStates: [WindowState]
    
    public init(windowStates: [WindowState]) {
        self.windowStates = windowStates
    }
}

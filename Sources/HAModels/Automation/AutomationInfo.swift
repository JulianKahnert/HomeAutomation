//
//  AutomationInfo.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 18.11.25.
//

// Information about automations
//
// This might be used as a DTO between the Server and the Controller.
public struct AutomationInfo: Identifiable, Sendable, Codable, Equatable {
    public let name: String
    public let isActive: Bool
    public let isRunning: Bool

    public var id: String { name }

    public init(name: String, isActive: Bool, isRunning: Bool) {
        self.name = name
        self.isActive = isActive
        self.isRunning = isRunning
    }
}

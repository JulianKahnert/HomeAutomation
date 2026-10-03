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
    public var isActive: Bool
    public var isRunning: Bool
    /// Type name of the automation, e.g. `MotionAtNight`; `nil` from servers that predate it.
    public var type: String?
    public var recordsRuns: Bool
    public var lastRun: AutomationRun?
    public var entities: [EntityId]

    public var id: String { name }

    public init(name: String, isActive: Bool, isRunning: Bool, type: String? = nil, recordsRuns: Bool = true, lastRun: AutomationRun? = nil, entities: [EntityId] = []) {
        self.name = name
        self.isActive = isActive
        self.isRunning = isRunning
        self.type = type
        self.recordsRuns = recordsRuns
        self.lastRun = lastRun
        self.entities = entities
    }
}

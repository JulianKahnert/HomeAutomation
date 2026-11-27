//
//  ActionLogItem.swift
//
//
//  Created by Julian Kahnert on 14.11.25.
//

import Foundation

public struct ActionLogItem: Identifiable, Sendable, Codable, Equatable {
    public enum Status: String, Sendable, Codable, CaseIterable {
        /// Sent to the adapter.
        case executed
        /// Skipped as a duplicate of a recently executed command.
        case cacheHit
        /// The adapter call threw.
        case failed
    }

    public let id: UUID
    public let timestamp: Date
    public let entityId: EntityId
    public let actionName: String
    public let detailDescription: String
    /// The `AutomationRun` that sent the command; `nil` for API calls.
    public let runId: UUID?
    public var status: Status
    /// Why the server wrote a radiator; `nil` for every other command.
    public let reason: HeatingWriteReason?
    /// The plan target at the time of a `plan` write; `nil` otherwise.
    public let planTargetInC: Double?
    /// The value a radiator command wrote: 1 or 0 for `setHeating`, the °C of `setTargetTemperature`; `nil` for every other command.
    public let value: Double?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        action: HomeManagableAction,
        status: Status = .executed,
        runId: UUID? = nil,
        reason: HeatingWriteReason? = nil,
        planTargetInC: Double? = nil
    ) {
        switch action {
        case .setHeating(_, let active): self.value = active ? 1 : 0
        case .setTargetTemperature(_, let celsius): self.value = celsius
        default: self.value = nil
        }
        self.id = id
        self.timestamp = timestamp
        self.entityId = action.entityId
        self.actionName = action.actionName
        self.detailDescription = action.description
        self.runId = runId
        self.status = status
        self.reason = reason
        self.planTargetInC = planTargetInC
    }

    public init(id: UUID, timestamp: Date, entityId: EntityId, actionName: String, detailDescription: String, status: Status, runId: UUID? = nil, reason: HeatingWriteReason? = nil, planTargetInC: Double? = nil, value: Double? = nil) {
        self.value = value
        self.id = id
        self.timestamp = timestamp
        self.entityId = entityId
        self.actionName = actionName
        self.detailDescription = detailDescription
        self.runId = runId
        self.status = status
        self.reason = reason
        self.planTargetInC = planTargetInC
    }

}

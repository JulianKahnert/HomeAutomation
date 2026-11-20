//
//  HeatingWrite.swift
//  HAModels
//

import Foundation

/// Why the server wrote a radiator. A fixed list on purpose: "observed" is not a reason, it is derived
/// when the Heizung tab is prepared (see the glossary).
public enum HeatingWriteReason: String, Sendable, Codable, CaseIterable {
    /// A switch point of the room's plan.
    case plan
    /// A window contact of the room opened or closed.
    case window
    /// A fireplace the room follows was switched on or off.
    case fireplace
    /// Everything else, e.g. a configuration deploy or a timeout.
    case system
}

/// Carries the reason of a radiator write down to `HomeManager.perform(_:)` without changing the
/// signature of `HomeManagable`, like `AutomationRunContext` does for the run id.
public enum HeatingWriteContext {
    public struct Context: Sendable, Equatable {
        public let reason: HeatingWriteReason
        /// The plan target at the time of the write; set for `plan` writes and the plan write after a deploy.
        public let planTargetInC: Double?

        public init(reason: HeatingWriteReason, planTargetInC: Double? = nil) {
            self.reason = reason
            self.planTargetInC = planTargetInC
        }
    }

    @TaskLocal public static var current: Context?

    /// Runs `operation` so that every radiator write inside it is recorded with `reason`.
    public static func withReason<Result>(_ reason: HeatingWriteReason,
                                          planTargetInC: Double? = nil,
                                          operation: () async throws -> Result) async rethrows -> Result {
        try await $current.withValue(Context(reason: reason, planTargetInC: planTargetInC), operation: operation)
    }
}

/// One write of the server to a radiator, persisted so the plan history and the events of the Heizung
/// tab can be built from what the server actually wrote.
public struct HeatingWrite: Identifiable, Sendable, Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    /// The radiator's entity; `entityId.placeId` is the room.
    public let entityId: EntityId
    public let reason: HeatingWriteReason
    /// `setHeating` or `setTargetTemperature`.
    public let actionName: String
    /// The value written by `setHeating`; `nil` for a target temperature.
    public let isActive: Bool?
    /// The value written by `setTargetTemperature`; `nil` for `setHeating`.
    public let targetTemperatureInC: Double?
    /// The plan target at the time of the write; `nil` for writes that do not follow the plan.
    public let planTargetInC: Double?

    public var placeId: String { entityId.placeId }

    public init(id: UUID = UUID(),
                timestamp: Date = Date(),
                entityId: EntityId,
                reason: HeatingWriteReason,
                actionName: String,
                isActive: Bool? = nil,
                targetTemperatureInC: Double? = nil,
                planTargetInC: Double? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.entityId = entityId
        self.reason = reason
        self.actionName = actionName
        self.isActive = isActive
        self.targetTemperatureInC = targetTemperatureInC
        self.planTargetInC = planTargetInC
    }

    /// The record of `action`, or `nil` when `action` is not a radiator write.
    public init?(action: HomeManagableAction, context: HeatingWriteContext.Context, at timestamp: Date = Date()) {
        switch action {
        case .setHeating(_, let active):
            self.init(timestamp: timestamp, entityId: action.entityId, reason: context.reason, actionName: action.actionName, isActive: active, planTargetInC: context.planTargetInC)
        case .setTargetTemperature(_, let celsius):
            self.init(timestamp: timestamp, entityId: action.entityId, reason: context.reason, actionName: action.actionName, targetTemperatureInC: celsius, planTargetInC: context.planTargetInC)
        default:
            return nil
        }
    }
}

/// Persistence of `HeatingWrite`s; implemented by the server's database.
public protocol HeatingWriteRepository: Sendable {
    func add(_ write: HeatingWrite) async throws
    /// The writes to the radiators of room `placeId` in `startDate ..< endDate` (open ends allowed),
    /// oldest first.
    func writes(placeId: String, startDate: Date?, endDate: Date?) async throws -> [HeatingWrite]
    func deleteWrites(olderThan date: Date) async throws
}

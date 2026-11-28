//
//  InMemoryHeatingCommands.swift
//  HomeAutomationKit
//

import Foundation
import HAModels

/// A radiator command as a test seeds it: the journal row plus the plan target that was current at the time.
struct HeatingFixture {
    let command: ActionLogItem
    let planTargetInC: Double?

    var timestamp: Date { command.timestamp }
    var placeId: String { command.placeId }

    init(timestamp: Date = Date(), entityId: EntityId, reason: HeatingWriteReason, actionName: String,
         isActive: Bool? = nil, targetTemperatureInC: Double? = nil, planTargetInC: Double? = nil) {
        let value = isActive.map { $0 ? 1.0 : 0.0 } ?? targetTemperatureInC
        command = ActionLogItem(id: UUID(), timestamp: timestamp, entityId: entityId, actionName: actionName, detailDescription: actionName,
                                status: .executed, reason: reason, value: value)
        self.planTargetInC = planTargetInC
    }

    /// The stored state of the room's plan target entity that goes with this write, `nil` without a plan target.
    func planTargetItem() -> EntityStorageItem? {
        planTargetInC.map { EntityStorageItem(entityId: HeatingRoomSources.planTargetId(placeId: placeId), timestamp: timestamp, targetTemperatureInC: $0, origin: .server) }
    }
}

/// The radiator commands the room detail reads, in memory.
actor InMemoryHeatingCommands: HeatingCommandSource {
    private let all: [ActionLogItem]

    init(_ writes: [HeatingFixture] = []) {
        all = writes.map(\.command)
    }

    func writes(placeId: String, startDate: Date?, endDate: Date?) -> [ActionLogItem] {
        requestedStarts.append(startDate)
        return all.filter { $0.placeId == placeId && $0.timestamp >= (startDate ?? .distantPast) && $0.timestamp < (endDate ?? .distantFuture) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// The `startDate` of every `writes` call, `nil` for an open start.
    private(set) var requestedStarts: [Date?] = []
}

/// A seeded radiator command without a plan target.
func seededWrite(timestamp: Date, entityId: EntityId, reason: HeatingWriteReason, actionName: String,
                 isActive: Bool? = nil, targetTemperatureInC: Double? = nil) -> ActionLogItem {
    HeatingFixture(timestamp: timestamp, entityId: entityId, reason: reason, actionName: actionName,
                   isActive: isActive, targetTemperatureInC: targetTemperatureInC).command
}

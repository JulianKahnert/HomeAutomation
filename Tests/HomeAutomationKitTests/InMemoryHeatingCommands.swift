//
//  InMemoryHeatingCommands.swift
//  HomeAutomationKit
//

import Foundation
import HAModels

/// The radiator commands the room detail reads, in memory.
actor InMemoryHeatingCommands: HeatingCommandSource {
    private let all: [HeatingWrite]

    init(_ writes: [HeatingWrite] = []) {
        all = writes
    }

    func writes(placeId: String, startDate: Date?, endDate: Date?) -> [HeatingWrite] {
        requestedStarts.append(startDate)
        return all.filter { $0.placeId == placeId && $0.timestamp >= (startDate ?? .distantPast) && $0.timestamp < (endDate ?? .distantFuture) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// The `startDate` of every `writes` call, `nil` for an open start.
    private(set) var requestedStarts: [Date?] = []
}

extension HeatingWrite {
    /// The stored state of the room's plan target entity that goes with this write, `nil` without a plan target.
    func planTargetItem() -> EntityStorageItem? {
        planTargetInC.map { EntityStorageItem(entityId: HeatingRoomSources.planTargetId(placeId: placeId), timestamp: timestamp, targetTemperatureInC: $0, origin: .server) }
    }
}

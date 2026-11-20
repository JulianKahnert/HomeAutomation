//
//  InMemoryHeatingWriteRepository.swift
//  HomeAutomationKit
//

import Foundation
import HAModels

actor InMemoryHeatingWriteRepository: HeatingWriteRepository {
    private(set) var all: [HeatingWrite] = []

    init(_ writes: [HeatingWrite] = []) {
        all = writes
    }

    func add(_ write: HeatingWrite) {
        all.append(write)
    }

    func writes(placeId: String, startDate: Date?, endDate: Date?) -> [HeatingWrite] {
        all.filter { $0.placeId == placeId && $0.timestamp >= (startDate ?? .distantPast) && $0.timestamp < (endDate ?? .distantFuture) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func lastWrite(placeId: String, radiatorName: String) -> HeatingWrite? {
        all.filter { $0.sentToDevice && $0.placeId == placeId && $0.entityId.name == radiatorName }.max { $0.timestamp < $1.timestamp }
    }

    func deleteWrites(olderThan date: Date) {
        all.removeAll { $0.timestamp < date }
    }
}

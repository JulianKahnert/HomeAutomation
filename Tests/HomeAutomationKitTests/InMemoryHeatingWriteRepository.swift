//
//  InMemoryHeatingWriteRepository.swift
//  HomeAutomationKit
//

import Foundation
import HAModels

actor InMemoryHeatingWriteRepository: HeatingWriteRepository {
    private(set) var all: [HeatingWrite] = []

    func add(_ write: HeatingWrite) {
        all.append(write)
    }

    func writes(placeId: String, startDate: Date?, endDate: Date?) -> [HeatingWrite] {
        all.filter { $0.placeId == placeId && (startDate == nil || $0.timestamp >= startDate!) && (endDate == nil || $0.timestamp < endDate!) }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func deleteWrites(olderThan date: Date) {
        all.removeAll { $0.timestamp < date }
    }
}

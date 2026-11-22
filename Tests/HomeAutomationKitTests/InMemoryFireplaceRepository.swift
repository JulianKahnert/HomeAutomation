//
//  InMemoryFireplaceRepository.swift
//  HomeAutomationKitTests
//

import Foundation
import HAModels

/// The fireplace switches a test seeds, answered like the database does.
actor InMemoryFireplaceRepository: FireplaceRepository {
    private(set) var all: [FireplaceSwitch]

    init(_ switches: [FireplaceSwitch] = []) {
        all = switches.sorted { $0.timestamp < $1.timestamp }
    }

    func add(_ fireplaceSwitch: FireplaceSwitch) async throws {
        all.append(fireplaceSwitch)
        all.sort { $0.timestamp < $1.timestamp }
    }

    func latest() async throws -> FireplaceSwitch? {
        all.last
    }

    func switches(from startDate: Date, to endDate: Date) async throws -> [FireplaceSwitch] {
        let before = all.last { $0.timestamp < startDate }
        return (before.map { [$0] } ?? []) + all.filter { $0.timestamp >= startDate && $0.timestamp < endDate }
    }
}

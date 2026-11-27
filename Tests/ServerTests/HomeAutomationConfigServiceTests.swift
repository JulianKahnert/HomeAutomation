//
//  HomeAutomationConfigServiceTests.swift
//  HomeAutomation
//

import Foundation
import HAImplementations
import HAModels
@testable import Server
import Synchronization
import Testing

struct HomeAutomationConfigServiceTests {
    @Test func savingStoresTheLocationWithTheAutomationsAndTheirActiveState() async throws {
        let persisted = Mutex<Data?>(nil)
        let service = HomeAutomationConfigService(
            location: Location(latitude: 1, longitude: 2),
            persist: { data in persisted.withLock { $0 = data } }
        )
        var maintenance = MaintenanceAutomation("Maintenance", at: Time(hour: 3, minute: 0))
        maintenance.isActive = false

        try await service.save([maintenance])

        let data = try #require(persisted.withLock { $0 })
        let config = try JSONDecoder().decode(ConfigDTO.self, from: data)
        #expect(config.location.latitude == 1)
        #expect(config.automations.map(\.automation.isActive) == [false])
    }

    @Test func savesRunOneAfterAnother() async throws {
        let active = Mutex(0)
        let overlapped = Mutex(false)
        let service = HomeAutomationConfigService(
            location: Location(latitude: 1, longitude: 2),
            persist: { _ in
                if active.withLock({ $0 += 1; return $0 }) > 1 { overlapped.withLock { $0 = true } }
                for _ in 0..<20 { await Task.yield() }
                active.withLock { $0 -= 1 }
            }
        )
        let maintenance = MaintenanceAutomation("Maintenance", at: Time(hour: 3, minute: 0))

        async let first: Void = service.save([maintenance])
        async let second: Void = service.save([maintenance])
        _ = try await (first, second)

        #expect(overlapped.withLock { $0 } == false)
    }
}

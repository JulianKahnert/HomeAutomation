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

        try await service.save([maintenance], location: nil)

        let data = try #require(persisted.withLock { $0 })
        let config = try JSONDecoder().decode(ConfigDTO.self, from: data)
        #expect(config.location.latitude == 1)
        #expect(config.automations.map(\.automation.isActive) == [false])
    }

    @Test func aDeployedLocationIsStoredWithTheAutomationsOfTheSameSave() async throws {
        let persisted = Mutex<Data?>(nil)
        let service = HomeAutomationConfigService(
            location: Location(latitude: 1, longitude: 2),
            persist: { data in persisted.withLock { $0 = data } }
        )

        try await service.save([MaintenanceAutomation("Maintenance", at: Time(hour: 3, minute: 0))], location: Location(latitude: 5, longitude: 6))

        let config = try JSONDecoder().decode(ConfigDTO.self, from: try #require(persisted.withLock { $0 }))
        #expect(config.location.latitude == 5)
        #expect(await service.location.latitude == 5)
    }
}

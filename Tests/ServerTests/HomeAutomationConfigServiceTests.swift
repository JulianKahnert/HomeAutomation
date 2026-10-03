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
    @Test func setAutomationActivePersistsTheNewState() async throws {
        let persisted = Mutex<Data?>(nil)
        let service = HomeAutomationConfigService(
            location: Location(latitude: 1, longitude: 2),
            automations: [MaintenanceAutomation("Maintenance", at: Time(hour: 3, minute: 0))],
            persist: { data in persisted.withLock { $0 = data } }
        )

        try await service.setAutomationActive(with: "Maintenance", to: false)

        let data = try #require(persisted.withLock { $0 })
        let config = try JSONDecoder().decode(ConfigDTO.self, from: data)
        #expect(config.location.latitude == 1)
        #expect(config.automations.map(\.automation.isActive) == [false])
    }
}

//
//  OriginTests.swift
//  HomeAutomation
//

@testable import Adapter
import Foundation
@testable import HAModels
@testable import Server
import Testing

struct OriginTests {
    private let entityId = EntityId(placeId: "room", name: "lamp", characteristicsName: nil, characteristic: .switcher)

    @Test("A change that comes in over the adapter link carries origin homekit")
    func adapterLinkStampsHomekit() {
        let item = EntityStorageItem(entityId: entityId, isDeviceOn: true, origin: .server)

        guard case .change(let stamped) = HomeEventReceiver.stamped(.change(entity: item)) else {
            Issue.record("expected a change")
            return
        }

        #expect(stamped.origin == .homekit)
        #expect(stamped.isDeviceOn == true)
    }

    @Test("A stored state keeps its origin", arguments: [Origin.homekit, Origin.server, Origin.job("valves")])
    func storedStateKeepsOrigin(origin: Origin) {
        let item = EntityStorageItem(entityId: entityId, isDeviceOn: true, origin: origin)

        let restored = EntityStorageDbRepository.mapDbItem(EntityStorageDbRepository.map(item))

        #expect(restored.origin == origin)
    }

    @Test("The API carries the origin of a change")
    func apiCarriesOrigin() {
        let item = EntityStorageItem(entityId: entityId, isDeviceOn: true, origin: .job("valves"))

        #expect(Components.Schemas.EntityHistoryItem(item).origin == "valves")
        #expect(EntityHistoryItem(item).origin == "valves")
    }
}

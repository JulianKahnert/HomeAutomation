//
//  HomekitInventoryTests.swift
//  HomeAutomationServer
//

@testable import Adapter
import Foundation
@testable import HAModels
@testable import Server
import StarActorSystem
import Synchronization
import Testing

/// The HomeKit inventory: the receiver hands the adapter's snapshot to the store, and a row fits its columns.
struct HomekitInventoryTests {
    static func item(room: String = "Bad", accessory: String = "Fenster", type: CharacteristicsType? = .contactSensor, value: String? = "0") -> HomeKitInventoryItem {
        HomeKitInventoryItem(
            homeName: "Home",
            roomName: room,
            accessoryName: accessory,
            manufacturer: "Eve",
            model: "Door",
            serviceType: "00000080-0000-1000-8000-0026BB765291",
            serviceName: "Contact",
            characteristicType: "0000006A-0000-1000-8000-0026BB765291",
            characteristicDescription: "Contact State",
            mappedType: type,
            isReadable: true,
            isNotifiable: true,
            isWritable: false,
            value: value
        )
    }

    @Test("The receiver hands the snapshot of the adapter to the store as it is")
    func receiverStoresTheSnapshot() async throws {
        let stored = Mutex<[HomeKitInventoryItem]?>(nil)
        let system = StarActorSystem(name: "inventory-test")
        let receiver = system.makeActor(id: .homeEventReceiver) {
            HomeEventReceiver(emit: { _ in }, storeInventory: { items in stored.withLock { $0 = items } }, actorSystem: system)
        }
        let snapshot = [Self.item(), Self.item(accessory: "Unbekannt", type: nil, value: nil)]

        try await receiver.process(inventory: snapshot)

        #expect(stored.withLock { $0 } == snapshot)
    }

    @Test("A failing store is reported back to the adapter")
    func receiverReportsAStoreFailure() async {
        struct Failure: Error {}
        let system = StarActorSystem(name: "inventory-test-failure")
        let receiver = system.makeActor(id: .homeEventReceiver) {
            HomeEventReceiver(emit: { _ in }, storeInventory: { _ in throw Failure() }, actorSystem: system)
        }
        await #expect(throws: Failure.self) { try await receiver.process(inventory: []) }
    }

    @Test("A row keeps a mapped type and cuts texts to the width of their columns")
    func rowFitsItsColumns() {
        var long = Self.item()
        long.accessoryName = String(repeating: "ä", count: 400)
        long.serviceType = String(repeating: "x", count: 100)
        long.value = String(repeating: "v", count: 300)
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let row = HomekitInventoryDbItem(long, syncedAt: syncedAt)

        #expect(row.accessoryName.unicodeScalars.count == HomekitInventoryDbItem.nameWidth)
        #expect(row.serviceType.count == HomekitInventoryDbItem.typeWidth)
        #expect(row.value?.count == HomekitInventoryDbItem.valueWidth)
        #expect(row.mappedType == "contactSensor")
        #expect(row.syncedAt == syncedAt)
        #expect(HomekitInventoryDbItem(Self.item(type: nil), syncedAt: syncedAt).mappedType == nil)
    }
}

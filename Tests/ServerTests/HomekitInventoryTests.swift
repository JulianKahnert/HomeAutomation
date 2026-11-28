//
//  HomekitInventoryTests.swift
//  HomeAutomationServer
//

import Foundation
@testable import HAModels
@testable import Server
import Synchronization
import Testing

/// The HomeKit inventory: flattened to rows, fitted to the columns, pulled and stored by the sync.
struct HomekitInventoryTests {
    static func characteristic(type: CharacteristicsType? = .contactSensor, value: String? = "0") -> HomeKitInventory.Characteristic {
        HomeKitInventory.Characteristic(
            type: "0000006A-0000-1000-8000-0026BB765291",
            typeDescription: "Contact State",
            isReadable: true,
            isNotifiable: true,
            isWritable: false,
            mappedType: type,
            value: value
        )
    }

    static func accessory(_ name: String, reachable: Bool = true, characteristics: [HomeKitInventory.Characteristic]) -> HomeKitInventory.Accessory {
        let service = HomeKitInventory.Service(
            type: "00000080-0000-1000-8000-0026BB765291",
            typeDescription: "Contact Sensor",
            name: "Contact",
            isPrimary: true,
            characteristics: characteristics
        )
        return HomeKitInventory.Accessory(
            name: name,
            manufacturer: "Eve",
            model: "Door",
            category: "Sensor",
            isReachable: reachable,
            services: [service]
        )
    }

    static func inventory(_ accessories: [(room: String, accessory: HomeKitInventory.Accessory)]) -> HomeKitInventory {
        let rooms = Dictionary(grouping: accessories, by: \.room).sorted { $0.key < $1.key }
            .map { HomeKitInventory.Room(name: $0.key, accessories: $0.value.map(\.accessory)) }
        return HomeKitInventory(homes: [HomeKitInventory.Home(name: "Home", rooms: rooms)])
    }

    static let sample = inventory([
        ("Bad", accessory("Fenster", characteristics: [characteristic()])),
        ("Bad", accessory("Kamera", reachable: false, characteristics: [characteristic(type: nil, value: nil), characteristic(type: nil)])),
        ("Küche", accessory("Lampe", characteristics: []))
    ])

    @Test("The inventory is one row per characteristic, with its home, room, accessory and service")
    func rowsAreOnePerCharacteristic() {
        let rows = Self.sample.rows

        #expect(rows.count == 3)
        #expect(rows.map(\.accessory.name) == ["Fenster", "Kamera", "Kamera"])
        #expect(rows.map(\.roomName) == ["Bad", "Bad", "Bad"])
        #expect(rows.first?.homeName == "Home")
        #expect(rows.first?.service.typeDescription == "Contact Sensor")
        #expect(rows.first?.accessory.services.isEmpty == true)
    }

    @Test("The summary counts everything, the unmapped characteristics and the unreachable accessories")
    func summaryCounts() {
        let expected = HomeKitInventory.Summary(
            homes: 1,
            rooms: 2,
            accessories: 3,
            services: 3,
            characteristics: 3,
            unmappedCharacteristics: 2,
            unreachableAccessories: 1
        )
        #expect(Self.sample.summary == expected)
        #expect(Self.sample.accessoryLines.contains("[Home] Bad / Kamera (Eve Door) UNREACHABLE: Contact Sensor"))
        #expect(Self.sample.accessoryLines.count == 3)
    }

    @Test("The model survives the wire")
    func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(Self.sample)
        #expect(try JSONDecoder().decode(HomeKitInventory.self, from: data) == Self.sample)
    }

    @Test("A row keeps a mapped type and cuts texts to the width of their columns")
    func rowFitsItsColumns() throws {
        let long = Self.inventory([("Bad", Self.accessory(String(repeating: "ä", count: 400), characteristics: [Self.characteristic(value: String(repeating: "v", count: 300))]))])
        let syncedAt = Date(timeIntervalSince1970: 1_800_000_000)

        let row = HomekitInventoryDbItem(try #require(long.rows.first), syncedAt: syncedAt)

        #expect(row.accessoryName.unicodeScalars.count == HomekitInventoryDbItem.nameWidth)
        #expect(row.value?.count == HomekitInventoryDbItem.valueWidth)
        #expect(row.mappedType == "contactSensor")
        #expect(row.isPrimaryService)
        #expect(row.syncedAt == syncedAt)
        #expect(HomekitInventoryDbItem(try #require(Self.sample.rows.last), syncedAt: syncedAt).mappedType == nil)
    }

    // MARK: - sync

    @Test("A refresh pulls the inventory and stores it with the time of the pull")
    func refreshStores() async {
        let stored = Mutex<[(HomeKitInventory, Date)]>([])
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let sync = HomekitInventorySync(
            fetch: { Self.sample },
            store: { inventory, date in stored.withLock { $0.append((inventory, date)) } },
            now: { moment }
        )

        #expect(await sync.refresh())

        #expect(stored.withLock { $0.map(\.0) } == [Self.sample])
        #expect(stored.withLock { $0.map(\.1) } == [moment])
    }

    @Test("Without a connected adapter nothing is stored")
    func refreshWithoutAdapterStoresNothing() async {
        let stored = Mutex(0)
        let sync = HomekitInventorySync(fetch: { nil }, store: { _, _ in stored.withLock { $0 += 1 } })

        #expect(await sync.refresh() == false)
        #expect(stored.withLock { $0 } == 0)
    }

    @Test("A failing pull or store is no crash and leaves the stored inventory alone")
    func refreshSurvivesFailures() async {
        struct Failure: Error {}
        let stored = Mutex(0)
        let failingFetch = HomekitInventorySync(fetch: { throw Failure() }, store: { _, _ in stored.withLock { $0 += 1 } })
        let failingStore = HomekitInventorySync(fetch: { Self.sample }, store: { _, _ in throw Failure() })

        #expect(await failingFetch.refresh() == false)
        #expect(await failingStore.refresh() == false)
        #expect(stored.withLock { $0 } == 0)
    }

    @Test("The sync refreshes at its start and on every completed handshake")
    func runRefreshesAtStartAndOnHandshake() async throws {
        let count = Mutex(0)
        let sync = HomekitInventorySync(fetch: { count.withLock { $0 += 1 }; return Self.sample }, store: { _, _ in })
        let (handshakes, continuation) = AsyncStream.makeStream(of: Void.self)
        let task = Task { await sync.run(handshakes: handshakes, interval: .seconds(3600)) }

        try await waitUntil { count.withLock { $0 } == 1 }
        continuation.yield()
        try await waitUntil { count.withLock { $0 } == 2 }
        task.cancel()
        continuation.finish()
        await task.value
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<500 where !condition() {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition())
    }
}

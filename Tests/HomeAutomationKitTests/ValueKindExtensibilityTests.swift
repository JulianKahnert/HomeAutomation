//
//  ValueKindExtensibilityTests.swift
//  HomeAutomation
//

import Foundation
@testable import HAModels
import Testing

/// Pins the shape that makes a new value kind cheap. Adding a kind touches these places, nothing else in
/// HAModels, the database or the API:
/// 1. a `CharacteristicsType` case (its raw value is the kind's name),
/// 2. its entry in `ValueDescriptor.descriptor(for:)` (shape, unit, display, storage rule; exhaustive, so the compiler asks),
/// 3. the adapter's mapping from the HomeKit characteristic to a value (`HomeKitCharacteristic` and a reader),
/// 4. optionally a typed accessor in `EntityStorageItem+TypedAccess.swift` for automations that want one.
struct ValueKindExtensibilityTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func itemCarriesOneValueAndNoFieldPerKind() {
        let item = EntityStorageItem(entityId: EntityId(placeId: "p", name: "e", characteristicsName: nil, characteristic: .switcher))
        let stored = Mirror(reflecting: item).children.compactMap(\.label)
        #expect(Set(stored) == ["entityId", "timestamp", "kind", "value", "origin", "lastReport"])
        let history = Mirror(reflecting: EntityHistoryItem(timestamp: date)).children.compactMap(\.label)
        #expect(Set(history) == ["id", "timestamp", "origin", "lastReport", "valueKind", "value"])
    }

    /// A kind needs no code in the wire format, the item or the history: whatever its descriptor says is carried.
    @Test(arguments: CharacteristicsType.allCases)
    func aKindTravelsWithItsDescriptorAlone(_ type: CharacteristicsType) throws {
        let descriptor = ValueDescriptor.descriptor(for: type)
        let value: Value
        switch descriptor.shape {
        case .bool: value = .bool(true)
        case .number: value = .number(type == .heatingMode ? 1 : 2)
        case .text: value = .text("0.5 0.25 1.0")
        case .textWithNumber: value = .text("running 1800000000.0")
        }
        let id = EntityId(placeId: "p", name: "e", characteristicsName: nil, characteristic: type)
        let item = try #require(EntityStorageItem(entityId: id, timestamp: date, kind: type.valueKind, value: value))

        let decoded = try JSONDecoder().decode(EntityStorageItem.self, from: JSONEncoder().encode(item))
        let history = EntityHistoryItem(item)

        #expect(decoded == item)
        #expect(history.valueKind == type.rawValue)
        #expect(history.value == value)
    }
}

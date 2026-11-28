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

    /// A kind needs no code in the wire format, the item or the history: whatever its descriptor says is carried.
    @Test(arguments: CharacteristicsType.allCases)
    func aKindTravelsWithItsDescriptorAlone(_ type: CharacteristicsType) throws {
        let value: Value
        switch ValueDescriptor.descriptor(for: type).shape {
        case .bool: value = .bool(true)
        case .number: value = .number(type == .heatingMode ? 1 : 2)
        case .text: value = .text("0.5 0.25 1.0")
        case .textWithNumber: value = .text("running 1800000000.0")
        }
        let id = EntityId(placeId: "p", name: "e", characteristicsName: nil, characteristic: type)
        let item = try #require(EntityStorageItem(entityId: id, timestamp: date, value: value))

        let decoded = try JSONDecoder().decode(EntityStorageItem.self, from: JSONEncoder().encode(item))
        let history = EntityHistoryItem(item)

        #expect(decoded == item)
        #expect(history.valueKind == type.rawValue)
        #expect(history.value == value)
    }
}

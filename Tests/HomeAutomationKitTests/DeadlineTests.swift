//
//  DeadlineTests.swift
//  HomeAutomationKitTests
//

import Foundation
@testable import HAModels
import Testing

struct DeadlineTests {
    private let end = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func textFormRoundTrips() throws {
        for deadline in [Deadline.none, .running(until: end), .overdue(since: end)] {
            #expect(Deadline(text: deadline.text) == deadline)
            #expect(Deadline(caseName: deadline.caseName, end: deadline.end?.timeIntervalSince1970) == deadline)
        }
        #expect(Deadline(text: "running") == nil)
        #expect(Deadline(text: "soon 5") == nil)
    }

    @Test func itemRoundTripsThroughTheGenericForm() throws {
        let id = EntityId.serverOwned(name: "Küche/Fenster", characteristic: .deadline)
        let item = EntityStorageItem(entityId: id, timestamp: end, deadline: .running(until: end), origin: .server)
        let generic = try #require(item.genericValue)
        #expect(generic.kind == CharacteristicsType.deadline.valueKind)
        #expect(generic.kind.descriptor?.shape == .textWithNumber)
        #expect(EntityStorageItem(entityId: id, timestamp: end, kind: generic.kind, value: generic.value, origin: .server) == item)
    }
}

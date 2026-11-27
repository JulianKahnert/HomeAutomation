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

    @Test func aDeadlineIsAServerOwnedTextWithNumber() throws {
        let id = EntityId.serverOwned(name: "Küche/Fenster", characteristic: .deadline)
        let item = EntityStorageItem(entityId: id, timestamp: end, deadline: .running(until: end), origin: .server)
        #expect(item.kind == .deadline)
        #expect(ValueDescriptor.descriptor(for: .deadline).shape == .textWithNumber)
        #expect(item.deadline == .running(until: end))
    }
}

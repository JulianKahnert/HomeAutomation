//
//  HeatingOverviewMappingTests.swift
//  HomeAutomationServer
//

import Foundation
import HAModels
@testable import Server
import Testing

@Suite("Heating overview wire format")
struct HeatingOverviewMappingTests {
    @Test("The overview carries the delta, the display name and the short label of the room")
    func overviewFields() throws {
        let room = HeatingOverviewRoom(placeId: "Bad - OG", name: "Bad Obergeschoss", shortName: "Bad", ist: 19, sollPlan: 21, istSource: .thermostats(["Thermo"]))

        let mapped = try #require(Components.Schemas.HeatingOverview(HeatingOverview(rooms: [room])).rooms.first)

        #expect(mapped.delta == -2)
        #expect(mapped.name == "Bad Obergeschoss")
        #expect(mapped.shortName == "Bad")
        #expect(mapped.placeId == "Bad - OG")
    }

    @Test("A room without actual value maps to nil for actual and delta")
    func nilsAreMapped() throws {
        let room = HeatingOverviewRoom(placeId: "Keller", name: "Keller", shortName: "Keller", ist: nil, sollPlan: 17, istSource: .thermostats(["Thermo"]))

        let mapped = try #require(Components.Schemas.HeatingOverview(HeatingOverview(rooms: [room])).rooms.first)

        #expect(mapped.ist == nil)
        #expect(mapped.delta == nil)
        #expect(mapped.sollPlan == 17)
    }
}

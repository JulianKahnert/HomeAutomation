//
//  EventLoopGaugeTests.swift
//  HomeAutomationServer
//

import Foundation
import HAModels
@testable import Server
import Testing

@Suite("Event loop backlog gauge")
struct EventLoopGaugeTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test("an event that waits in the stream ages before the loop takes it")
    func waitingEventsAge() {
        let gauge = EventLoopGauge()
        gauge.stamp(at: start)
        gauge.stamp(at: start.addingTimeInterval(10))

        #expect(gauge.age(now: start.addingTimeInterval(30)) == 30)
    }

    @Test("the age is the one of the oldest event the loop has not finished, whether waiting or being handled")
    func ageFollowsTheOldestUnfinishedEvent() {
        let gauge = EventLoopGauge()
        gauge.stamp(at: start)
        gauge.stamp(at: start.addingTimeInterval(10))

        gauge.took()
        #expect(gauge.age(now: start.addingTimeInterval(30)) == 30)
        gauge.finished()
        #expect(gauge.age(now: start.addingTimeInterval(30)) == 20)
        gauge.took()
        gauge.finished()
        #expect(gauge.age(now: start.addingTimeInterval(30)) == 0)
    }

    @Test("one critical log above the limit, again only after the backlog drained")
    func reportsOncePerBacklog() {
        let gauge = EventLoopGauge()
        gauge.stamp(at: start)

        #expect(gauge.reportsBacklog(olderThan: 60, now: start.addingTimeInterval(30)) == nil)
        #expect(gauge.reportsBacklog(olderThan: 60, now: start.addingTimeInterval(90)) == 90)
        #expect(gauge.reportsBacklog(olderThan: 60, now: start.addingTimeInterval(120)) == nil)
        gauge.took()
        gauge.finished()
        #expect(gauge.reportsBacklog(olderThan: 60, now: start.addingTimeInterval(130)) == nil)
        gauge.stamp(at: start.addingTimeInterval(130))
        #expect(gauge.reportsBacklog(olderThan: 60, now: start.addingTimeInterval(200)) == 70)
    }
}

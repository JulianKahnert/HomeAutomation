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
    private let t0 = Date(timeIntervalSince1970: 1_000)

    @Test("an event that waits in the stream ages before the loop takes it")
    func waitingEventsAge() {
        let gauge = EventLoopGauge()
        gauge.stamp(at: t0)
        gauge.stamp(at: t0.addingTimeInterval(10))

        #expect(gauge.age(now: t0.addingTimeInterval(30)) == 30)
    }

    @Test("the age is the one of the oldest event the loop has not finished, whether waiting or being handled")
    func ageFollowsTheOldestUnfinishedEvent() {
        let gauge = EventLoopGauge()
        gauge.stamp(at: t0)
        gauge.stamp(at: t0.addingTimeInterval(10))

        gauge.took()
        #expect(gauge.age(now: t0.addingTimeInterval(30)) == 30)
        gauge.finished()
        #expect(gauge.age(now: t0.addingTimeInterval(30)) == 20)
        gauge.took()
        gauge.finished()
        #expect(gauge.age(now: t0.addingTimeInterval(30)) == 0)
    }

    @Test("one critical log above the limit, again only after the backlog drained")
    func reportsOncePerBacklog() {
        let gauge = EventLoopGauge()
        gauge.stamp(at: t0)

        #expect(gauge.reportsBacklog(olderThan: 60, now: t0.addingTimeInterval(30)) == nil)
        #expect(gauge.reportsBacklog(olderThan: 60, now: t0.addingTimeInterval(90)) == 90)
        #expect(gauge.reportsBacklog(olderThan: 60, now: t0.addingTimeInterval(120)) == nil)
        gauge.took()
        gauge.finished()
        #expect(gauge.reportsBacklog(olderThan: 60, now: t0.addingTimeInterval(130)) == nil)
        gauge.stamp(at: t0.addingTimeInterval(130))
        #expect(gauge.reportsBacklog(olderThan: 60, now: t0.addingTimeInterval(200)) == 70)
    }
}

//
//  SchedulerTests.swift
//  HomeAutomation
//

import Foundation
@testable import Server
import Testing

private actor ManualClock: SchedulerClock {
    private var current: Date
    private var waiters: [(Date, CheckedContinuation<Void, any Error>)] = []

    init(_ start: Date) { current = start }

    nonisolated var now: Date { Date(timeIntervalSince1970: nowValue.value) }
    nonisolated private let nowValue = Box()

    func sleep(until date: Date) async throws {
        try await withCheckedThrowingContinuation { waiters.append((date, $0)) }
    }

    func advance(to date: Date) {
        current = date
        nowValue.value = date.timeIntervalSince1970
        let due = waiters.filter { $0.0 <= date }
        waiters.removeAll { $0.0 <= date }
        due.forEach { $0.1.resume() }
    }

    var sleepingUntil: [Date] { waiters.map(\.0) }

    final class Box: @unchecked Sendable {
        var value: Double = 0
    }
}

private struct Gate: Sendable {
    let stream: AsyncStream<Void>
    let continuation: AsyncStream<Void>.Continuation
    init() { (stream, continuation) = AsyncStream.makeStream() }
    func wait() async { for await _ in stream { return } }
    func open() { continuation.yield() }
}

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Date] = []
    func add(_ date: Date) { lock.lock(); items.append(date); lock.unlock() }
    var dates: [Date] { lock.lock(); defer { lock.unlock() }; return items }
}

private struct TestJob: ScheduledJob {
    var name = "job"
    var cadence: Duration = .minutes(1)
    var runsAtStart = false
    var body: @Sendable (Date) async throws -> Void
    func run(plannedAt: Date) async throws { try await body(plannedAt) }
}

private struct Failure: Error {}

private func eventually(_ condition: () async -> Bool) async {
    for _ in 0..<500 {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

struct SchedulerTests {
    private let t0 = Date(timeIntervalSince1970: 6000 + 20) // 20 s past a full minute

    @Test func firesOnTheFullMinuteAndPassesThePlannedDate() async {
        let clock = ManualClock(t0)
        await clock.advance(to: t0)
        let seen = Recorder()
        let scheduler = Scheduler(clock: clock, jobs: [TestJob { seen.add($0) }])
        let task = Task { await scheduler.run() }

        await eventually { await clock.sleepingUntil == [Date(timeIntervalSince1970: 6060)] }
        #expect(seen.dates.isEmpty)
        await clock.advance(to: Date(timeIntervalSince1970: 6060))
        await eventually { seen.dates.count == 1 }
        #expect(seen.dates == [Date(timeIntervalSince1970: 6060)])
        task.cancel()
    }

    @Test func aLateWakeUpSkipsTheMissedMinutes() async {
        let clock = ManualClock(t0)
        await clock.advance(to: t0)
        let seen = Recorder()
        let scheduler = Scheduler(clock: clock, jobs: [TestJob { seen.add($0) }])
        let task = Task { await scheduler.run() }
        await eventually { await clock.sleepingUntil == [Date(timeIntervalSince1970: 6060)] }

        // Ten minutes late: the job runs once for the minute it woke for, then waits for the next full minute.
        let late = Date(timeIntervalSince1970: 6060 + 600 + 20)
        await clock.advance(to: late)
        await eventually { seen.dates.count == 1 }

        await eventually { await clock.sleepingUntil == [Date(timeIntervalSince1970: 6720)] }
        #expect(await clock.sleepingUntil == [Date(timeIntervalSince1970: 6720)])
        #expect(seen.dates == [Date(timeIntervalSince1970: 6060)])
        task.cancel()
    }

    @Test func cadenceSelectsTheMinutes() async {
        let seen = Recorder()
        let scheduler = Scheduler(clock: ManualClock(t0), jobs: [TestJob(cadence: .minutes(5)) { seen.add($0) }])
        await scheduler.tick(plannedAt: Date(timeIntervalSince1970: 6060)) // minute 101
        await scheduler.tick(plannedAt: Date(timeIntervalSince1970: 6000)) // minute 100
        await eventually { seen.dates.count == 1 }
        #expect(seen.dates == [Date(timeIntervalSince1970: 6000)])
    }

    @Test func slowJobNeitherStartsTwiceNorBlocksOthers() async {
        let gate = Gate()
        let slow = Recorder()
        let fast = Recorder()
        let scheduler = Scheduler(clock: ManualClock(t0), jobs: [
            TestJob(name: "slow") { slow.add($0); await gate.wait() },
            TestJob(name: "fast") { fast.add($0) }
        ])
        await scheduler.tick(plannedAt: Date(timeIntervalSince1970: 6000))
        await eventually { slow.dates.count == 1 && fast.dates.count == 1 }
        await scheduler.tick(plannedAt: Date(timeIntervalSince1970: 6060))
        await eventually { fast.dates.count == 2 }
        #expect(slow.dates.count == 1)

        gate.open()
        await eventually { await scheduler.lastSuccesses["slow"] != nil }
        await scheduler.tick(plannedAt: Date(timeIntervalSince1970: 6120))
        await eventually { slow.dates.count == 2 }
        gate.open()
        #expect(slow.dates.count == 2)
    }

    @Test func failingJobDoesNotStopOthersAndHasNoSuccess() async {
        let ok = Recorder()
        let scheduler = Scheduler(clock: ManualClock(t0), jobs: [
            TestJob(name: "bad") { _ in throw Failure() },
            TestJob(name: "good") { ok.add($0) }
        ])
        await scheduler.tick(plannedAt: Date(timeIntervalSince1970: 6000))
        await scheduler.tick(plannedAt: Date(timeIntervalSince1970: 6060))
        await eventually { ok.dates.count == 2 }
        await eventually { await scheduler.lastSuccesses["good"] != nil }
        let successes = await scheduler.lastSuccesses
        #expect(successes["bad"] == nil)
        #expect(successes["good"] != nil)
    }

    @Test func recordsTheLastSuccessFromTheClock() async {
        let clock = ManualClock(t0)
        await clock.advance(to: Date(timeIntervalSince1970: 6065))
        let scheduler = Scheduler(clock: clock, jobs: [TestJob { _ in }])
        await scheduler.tick(plannedAt: Date(timeIntervalSince1970: 6060))
        await eventually { await scheduler.lastSuccesses["job"] != nil }
        #expect(await scheduler.lastSuccesses["job"] == Date(timeIntervalSince1970: 6065))
    }

    @Test func runsAtStartOnce() async {
        let clock = ManualClock(t0)
        await clock.advance(to: t0)
        let seen = Recorder()
        let scheduler = Scheduler(clock: clock, jobs: [TestJob(runsAtStart: true) { seen.add($0) }])
        let task = Task { await scheduler.run() }
        await eventually { seen.dates.count == 1 }
        #expect(seen.dates == [t0])
        task.cancel()
    }
}

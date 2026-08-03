//
//  AsyncDebouncerTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 03.08.26.
//

import Foundation
@testable import Shared
import Testing

/// Records how often the debounced operation ran, whether two runs ever overlapped and whether a run
/// was cancelled while in flight.
private actor RunRecorder {
    private(set) var runs = 0
    private(set) var maxConcurrentRuns = 0
    private(set) var startedRuns = 0
    private(set) var wasCancelled = false
    private var activeRuns = 0

    private let runDuration: Duration?

    init(runDuration: Duration? = nil) {
        self.runDuration = runDuration
    }

    func run() async {
        startedRuns += 1
        activeRuns += 1
        maxConcurrentRuns = max(maxConcurrentRuns, activeRuns)

        if let runDuration {
            do {
                // deliberately not `try?` — that would swallow the cancellation signal
                try await Task.sleep(for: runDuration)
            } catch {
                wasCancelled = true
            }
        }
        if Task.isCancelled {
            wasCancelled = true
        }

        activeRuns -= 1
        runs += 1
    }

    func waitForStart(timeout: Duration = .seconds(1)) async {
        let deadline = ContinuousClock.now + timeout
        while startedRuns == 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
    }
}

struct AsyncDebouncerTests {

    @Test("A burst results in exactly one trailing run")
    func burstCollapsesIntoOneRun() async {
        let recorder = RunRecorder()
        let debouncer = AsyncDebouncer(delay: .milliseconds(50)) { await recorder.run() }

        for _ in 0..<10 {
            await debouncer.schedule()
        }

        #expect(await recorder.runs == 0) // nothing ran yet — the delay is still trailing

        try? await Task.sleep(for: .milliseconds(300))
        #expect(await recorder.runs == 1)
        #expect(await recorder.maxConcurrentRuns == 1)
    }

    @Test("Requests during a run produce exactly one follow-up run")
    func requestsDuringRunCoalesceIntoOneFollowUp() async {
        let recorder = RunRecorder(runDuration: .milliseconds(100))
        let debouncer = AsyncDebouncer(delay: .milliseconds(10)) { await recorder.run() }

        let firstRun = Task { await debouncer.runNow() }
        await recorder.waitForStart()

        for _ in 0..<5 {
            await debouncer.runNow()
        }
        await firstRun.value

        // the first run plus a single follow-up covering all 5 requests
        #expect(await recorder.runs == 2)
        #expect(await recorder.maxConcurrentRuns == 1)
    }

    @Test("A pending trailing run is absorbed by a run in flight")
    func pendingRunIsAbsorbed() async {
        let recorder = RunRecorder(runDuration: .milliseconds(100))
        let debouncer = AsyncDebouncer(delay: .milliseconds(10)) { await recorder.run() }

        let firstRun = Task { await debouncer.runNow() }
        await recorder.waitForStart()

        await debouncer.schedule()
        await firstRun.value

        // the scheduled run fires while the first one is still in flight
        try? await Task.sleep(for: .milliseconds(300))
        #expect(await recorder.runs == 2)
        #expect(await recorder.maxConcurrentRuns == 1)
    }

    @Test("The immediate path skips the delay")
    func immediateRunSkipsDelay() async {
        let recorder = RunRecorder()
        let debouncer = AsyncDebouncer(delay: .seconds(60)) { await recorder.run() }

        let start = ContinuousClock.now
        await debouncer.runNow()
        let duration = start.duration(to: .now)

        #expect(await recorder.runs == 1)
        #expect(duration < .seconds(1))
    }

    @Test("The immediate path absorbs a pending trailing run")
    func immediateRunAbsorbsPendingRun() async {
        let recorder = RunRecorder()
        let debouncer = AsyncDebouncer(delay: .milliseconds(50)) { await recorder.run() }

        await debouncer.schedule()
        await debouncer.runNow()

        try? await Task.sleep(for: .milliseconds(300))
        #expect(await recorder.runs == 1)
    }

    @Test("Cancelling drops a pending trailing run")
    func cancelPendingDropsScheduledRun() async {
        let recorder = RunRecorder()
        let debouncer = AsyncDebouncer(delay: .milliseconds(50)) { await recorder.run() }

        await debouncer.schedule()
        await debouncer.cancelPending()

        try? await Task.sleep(for: .milliseconds(300))
        #expect(await recorder.runs == 0)
    }

    @Test("Requests arriving faster than the delay still run within maxDelay")
    func maxDelayCapsAContinuousBurst() async {
        let recorder = RunRecorder()
        let debouncer = AsyncDebouncer(delay: .milliseconds(100), maxDelay: .milliseconds(300)) { await recorder.run() }

        // requests keep arriving faster than the debounce delay for well beyond maxDelay
        let start = ContinuousClock.now
        while start.duration(to: .now) < .milliseconds(700) {
            await debouncer.schedule()
            try? await Task.sleep(for: .milliseconds(20))
        }

        // the cap forced a run while the requests were still coming in
        #expect(await recorder.startedRuns >= 1)
        #expect(await recorder.wasCancelled == false)
    }

    @Test("A run in flight is never cancelled by the debouncer")
    func runInFlightIsNotCancelled() async {
        let recorder = RunRecorder(runDuration: .milliseconds(100))
        let debouncer = AsyncDebouncer(delay: .milliseconds(20)) { await recorder.run() }

        // started via the debounced path, so a delay task hands the run over
        await debouncer.schedule()
        await recorder.waitForStart()

        // none of these may touch the operation that is already running
        await debouncer.schedule()
        await debouncer.runNow()
        await debouncer.cancelPending()

        try? await Task.sleep(for: .milliseconds(500))
        #expect(await recorder.wasCancelled == false)
        #expect(await recorder.maxConcurrentRuns == 1)
        #expect(await recorder.runs == 2) // the first run plus one follow-up for the later requests
    }
}

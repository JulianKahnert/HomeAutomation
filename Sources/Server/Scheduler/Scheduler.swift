//
//  Scheduler.swift
//  HomeAutomationServer
//

import Foundation
import Logging
import Shared

/// A job with a cadence. The ``Scheduler`` calls it; it never loops or sleeps itself.
protocol ScheduledJob: Sendable {
    var name: String { get }
    /// A whole number of minutes; the job runs on every full minute that is a multiple of it.
    var cadence: Duration { get }
    /// Also run once when the scheduler starts, before the first aligned minute.
    var runsAtStart: Bool { get }
    func run(plannedAt: Date) async throws
}

extension ScheduledJob {
    var runsAtStart: Bool { false }
}

/// The time source of the ``Scheduler``, replaced in tests.
protocol SchedulerClock: Sendable {
    var now: Date { get }
    func sleep(until date: Date) async throws
}

struct SystemSchedulerClock: SchedulerClock {
    var now: Date { Date() }

    func sleep(until date: Date) async throws {
        try await Task.sleep(for: .seconds(max(0, date.timeIntervalSinceNow)))
    }
}

/// Calls jobs on the full minute and passes the planned date on. Every run gets its own task, so a slow job
/// delays neither the clock nor another job; a run is skipped while the previous run of the same job is still
/// running. A failing job is logged and does not stop the others. Knows no table.
actor Scheduler: Log {
    private let clock: any SchedulerClock
    private let jobs: [any ScheduledJob]
    private var running: Set<String> = []
    private var successes: [String: Date] = [:]
    private let disturbances = Disturbances<String>()

    init(clock: any SchedulerClock = SystemSchedulerClock(), jobs: [any ScheduledJob]) {
        self.clock = clock
        self.jobs = jobs
    }

    /// The time of the last successful run per job name; a job that never succeeded is absent.
    var lastSuccesses: [String: Date] { successes }

    func run() async {
        let started = clock.now
        for job in jobs where job.runsAtStart {
            start(job, plannedAt: started)
        }
        var next = Self.nextMinute(after: started)
        while !Task.isCancelled {
            do {
                try await clock.sleep(until: next)
            } catch {
                return
            }
            tick(plannedAt: next)
            next = next.addingTimeInterval(60)
        }
    }

    /// Starts every job that is due at `planned`; returns without waiting for them.
    func tick(plannedAt planned: Date) {
        let minute = Int((planned.timeIntervalSince1970 / 60).rounded(.down))
        for job in jobs {
            let every = max(1, Int(job.cadence.timeInterval / 60))
            guard minute % every == 0 else { continue }
            start(job, plannedAt: planned)
        }
    }

    private func start(_ job: any ScheduledJob, plannedAt planned: Date) {
        guard running.insert(job.name).inserted else {
            log.warning("Skipping a job: the previous run is still running", metadata: ["job": "\(job.name)"])
            return
        }
        Task {
            await execute(job, plannedAt: planned)
        }
    }

    private func execute(_ job: any ScheduledJob, plannedAt planned: Date) async {
        do {
            try await job.run(plannedAt: planned)
            successes[job.name] = clock.now
            if await disturbances.recovered(job.name) {
                log.info("Job works again", metadata: ["job": "\(job.name)"])
            }
        } catch {
            // Once per disturbance: a source that stays down is not logged on every run.
            if await disturbances.began(job.name) {
                log.error("Job failed", metadata: ["job": "\(job.name)", "error": "\(error)"])
            } else {
                log.debug("Job still failing", metadata: ["job": "\(job.name)", "error": "\(error)"])
            }
        }
        running.remove(job.name)
    }

    static func nextMinute(after date: Date) -> Date {
        Date(timeIntervalSince1970: ((date.timeIntervalSince1970 / 60).rounded(.down) + 1) * 60)
    }
}

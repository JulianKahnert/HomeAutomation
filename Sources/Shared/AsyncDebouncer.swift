//
//  AsyncDebouncer.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 03.08.26.
//

/// Collapses a burst of requests into a single run of `operation` and never lets two runs overlap.
///
/// `schedule()` (re)starts a trailing delay, so a burst settles into exactly one run — but never
/// later than `maxDelay` after the first request of that burst, so requests arriving faster than
/// `delay` for minutes on end cannot starve the operation. `runNow()` skips the delay for requests
/// that must not be deferred, but is still serialized against a run in flight. Requests arriving
/// while `operation` runs are not dropped: however many arrive, they produce exactly one follow-up
/// run.
///
/// The operation runs in a task the debouncer never cancels, so requests and cancellation can only
/// ever affect a run that has not started yet.
public actor AsyncDebouncer {
    private let delay: Duration
    private let maxDelay: Duration
    private let operation: @Sendable () async -> Void

    private var delayTask: Task<Void, Never>?
    private var runTask: Task<Void, Never>?
    /// When the requests coalesced so far have to run at the latest — set by the first request of a
    /// burst, not extended by the ones following it.
    private var runBy: ContinuousClock.Instant?
    /// Set while a run is in flight to remember that its result is already stale.
    private var isDirty = false

    public init(delay: Duration = .seconds(5), maxDelay: Duration = .seconds(30), operation: @escaping @Sendable () async -> Void) {
        self.delay = delay
        self.maxDelay = maxDelay
        self.operation = operation
    }

    /// Request a run once `delay` has passed without a further request, at the latest `maxDelay`
    /// after the first request of the current burst.
    public func schedule() {
        let now = ContinuousClock.now
        let deadline = runBy ?? now.advanced(by: maxDelay)
        runBy = deadline
        let wait = min(delay, now.duration(to: deadline))

        delayTask?.cancel()
        delayTask = Task {
            do {
                try await Task.sleep(for: max(.zero, wait))
            } catch {
                // superseded by a later request, or the pending run was cancelled
                return
            }
            guard !Task.isCancelled else { return }

            // Drop this handle before handing the request to the runner: from here on the debouncer
            // holds nothing it could cancel, so the operation always runs to completion.
            delayTask = nil
            runBy = nil
            startRun()
        }
    }

    /// Request a run without waiting for the debounce delay, absorbing a pending trailing run.
    ///
    /// Returns once the run this call started has finished — or immediately if a run was already in
    /// flight, since that run will pick the request up.
    public func runNow() async {
        cancelPending()
        await startRun()?.value
    }

    /// Drop a pending trailing run. A run already in flight is unaffected.
    public func cancelPending() {
        delayTask?.cancel()
        delayTask = nil
        runBy = nil
    }

    /// - Returns: The task running the operation, but only if this call started it.
    @discardableResult
    private func startRun() -> Task<Void, Never>? {
        guard runTask == nil else {
            isDirty = true
            return nil
        }

        let task = Task { await drain() }
        runTask = task
        return task
    }

    private func drain() async {
        repeat {
            isDirty = false
            await operation()
        } while isDirty

        runTask = nil
    }
}

//
//  ManualSleeper.swift
//  HomeAutomationKitTests
//

import Synchronization

/// A controllable stand-in for `Task.sleep`: every sleep stays suspended until the test calls
/// ``wake()``, so periodic work runs without real waiting. Cancelling the sleeping task ends its
/// sleep with `CancellationError`, like `Task.sleep`.
final class ManualSleeper: Sendable {
    private struct Sleep {
        let id: Int
        let duration: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var nextId = 0
        var sleeps: [Sleep] = []
        var waiters: [CheckedContinuation<Duration, Never>] = []
    }

    private let state = Mutex(State())

    func sleep(for duration: Duration) async throws {
        let id = state.withLock { state in
            defer { state.nextId += 1 }
            return state.nextId
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let waiters = state.withLock { state in
                    state.sleeps.append(Sleep(id: id, duration: duration, continuation: continuation))
                    defer { state.waiters = [] }
                    return state.waiters
                }
                waiters.forEach { $0.resume(returning: duration) }
                if Task.isCancelled {
                    cancel(id)
                }
            }
        } onCancel: {
            cancel(id)
        }
    }

    /// Waits until a sleep is suspended and returns its duration.
    func nextSleep() async -> Duration {
        await withCheckedContinuation { continuation in
            let duration = state.withLock { state in
                if let sleep = state.sleeps.first {
                    return Optional(sleep.duration)
                }
                state.waiters.append(continuation)
                return nil
            }
            if let duration {
                continuation.resume(returning: duration)
            }
        }
    }

    /// Ends every suspended sleep, as if its time had passed.
    func wake() {
        let sleeps = state.withLock { state in
            defer { state.sleeps = [] }
            return state.sleeps
        }
        sleeps.forEach { $0.continuation.resume() }
    }

    private func cancel(_ id: Int) {
        let sleep = state.withLock { state -> Sleep? in
            guard let index = state.sleeps.firstIndex(where: { $0.id == id }) else { return nil }
            return state.sleeps.remove(at: index)
        }
        sleep?.continuation.resume(throwing: CancellationError())
    }
}

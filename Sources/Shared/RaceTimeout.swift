//
//  RaceTimeout.swift
//  Shared
//

import Foundation

/// Runs `operation` against a timer and returns whichever ends first. Unlike a task group, it does not wait for the
/// loser: an `operation` that ignores cancellation (a database query, an actor hop) cannot hold the answer back.
/// - Throws: `error` when the timeout wins, otherwise what `operation` throws; `CancellationError` without starting
///   `operation` when the caller is already cancelled.
public func raceTimeout<T: Sendable>(_ timeout: Duration,
                                     timeoutError error: @escaping @Sendable () -> any Error,
                                     operation: @escaping @Sendable () async throws -> T) async throws -> T {
    // A caller that is already cancelled starts no work.
    try Task.checkCancellation()
    let (results, continuation) = AsyncStream<Result<T, any Error>>.makeStream()
    let work = Task {
        do {
            continuation.yield(.success(try await operation()))
        } catch {
            continuation.yield(.failure(error))
        }
    }
    let timer = Task {
        do {
            try await Task.sleep(for: timeout)
            continuation.yield(.failure(error()))
        } catch {}
    }
    defer {
        work.cancel()
        timer.cancel()
        continuation.finish()
    }
    for await result in results {
        return try result.get()
    }
    throw CancellationError()
}

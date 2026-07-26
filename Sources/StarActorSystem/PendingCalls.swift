//
//  PendingCalls.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 26.07.26.
//

import Foundation

/// Book-keeping for in-flight outbound remote calls.
///
/// Guarantees that every registered call resumes exactly once — via reply,
/// timeout, or `failAll` — and never leaks a continuation. A reply that
/// arrives between `begin` and `wait` is buffered (`earlyResults`) so the
/// send/wait race is harmless.
actor PendingCalls {
    private var continuations: [UUID: CheckedContinuation<ReplyEnvelope, any Error>] = [:]
    private var earlyResults: [UUID: Result<ReplyEnvelope, any Error>] = [:]
    private var timeoutTasks: [UUID: Task<Void, Never>] = [:]
    private var open: Set<UUID> = []

    /// Register a call as in-flight. Must be called before the frame is sent.
    func begin(_ id: UUID) {
        open.insert(id)
    }

    /// Await the reply for a call previously registered via `begin`.
    func wait(for id: UUID, timeout: Duration) async throws -> ReplyEnvelope {
        if let result = earlyResults.removeValue(forKey: id) {
            open.remove(id)
            return try result.get()
        }
        guard open.contains(id) else {
            throw StarRemoteCallError(message: "remote call \(id) was never registered")
        }
        return try await withCheckedThrowingContinuation { continuation in
            continuations[id] = continuation
            timeoutTasks[id] = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self.settle(id, with: .failure(StarRemoteCallError(message: "remote call timed out after \(timeout)")))
            }
        }
    }

    /// Complete a call exactly once; later settles for the same ID are ignored.
    func settle(_ id: UUID, with result: Result<ReplyEnvelope, any Error>) {
        guard open.contains(id) else { return }
        timeoutTasks.removeValue(forKey: id)?.cancel()
        if let continuation = continuations.removeValue(forKey: id) {
            open.remove(id)
            continuation.resume(with: result)
        } else {
            // `wait` not reached yet — buffer so it resolves immediately.
            earlyResults[id] = result
        }
    }

    /// Fail every in-flight call (connection lost or replaced).
    func failAll(_ error: any Error) {
        for id in open {
            settle(id, with: .failure(error))
        }
    }
}

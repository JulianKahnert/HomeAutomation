//
//  RaceTimeoutTests.swift
//  SharedTests
//

import Foundation
import Shared
import Testing

struct RaceTimeoutTests {
    private struct TimedOut: Error {}

    @Test func answersAtTheTimeoutEvenWhenTheOperationIgnoresCancellation() async {
        let (gate, release) = AsyncStream<Void>.makeStream()
        defer { release.finish() }

        await #expect(throws: TimedOut.self) {
            try await raceTimeout(.milliseconds(20), timeoutError: { TimedOut() }, operation: {
                // Ignores cancellation: only the gate ends it, and the gate stays closed until the test ends.
                for await _ in gate {}
                return 1
            })
        }
    }

    @Test func returnsTheResultOfAFastOperation() async throws {
        let value = try await raceTimeout(.seconds(5), timeoutError: { TimedOut() }, operation: { 42 })
        #expect(value == 42)
    }

    @Test func rethrowsTheErrorOfTheOperation() async {
        await #expect(throws: CancellationError.self) {
            try await raceTimeout(.seconds(5), timeoutError: { TimedOut() }, operation: { throw CancellationError() })
        }
    }
}

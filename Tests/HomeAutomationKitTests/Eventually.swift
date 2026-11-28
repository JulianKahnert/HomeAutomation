//
//  Eventually.swift
//  HomeAutomationKitTests
//

import Testing

/// Polls until `condition` holds and records an issue when it does not within `timeout`, so a broken condition
/// fails the test with its comment instead of hanging the suite.
nonisolated(nonsending) func eventually(
    timeout: Duration = .seconds(5),
    _ comment: Comment,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () async -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(1))
    }
    Issue.record("Did not happen within \(timeout): \(comment)", sourceLocation: sourceLocation)
}

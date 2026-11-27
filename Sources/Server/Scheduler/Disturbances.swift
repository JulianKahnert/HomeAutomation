//
//  Disturbances.swift
//  HomeAutomationServer
//

/// Remembers which keys are failing, so a failure is logged once per disturbance and not on every run.
actor Disturbances<Key: Hashable & Sendable> {
    private var failing: Set<Key> = []

    /// `true` for the first failure after the key worked (or was never seen).
    func began(_ key: Key) -> Bool { failing.insert(key).inserted }

    /// `true` when the key was failing and works again.
    func recovered(_ key: Key) -> Bool { failing.remove(key) != nil }
}

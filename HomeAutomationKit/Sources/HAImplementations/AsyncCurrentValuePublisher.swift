//
//  AsyncCurrentValuePublisher.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 07.11.24.
//

actor AsyncCurrentValuePublisher<Value: Sendable> {
    private var latestValue: Value?
    private var continuations: [CheckedContinuation<Value, Never>] = []

    init() {}

    func send(_ value: Value) {
        latestValue = value

        // notify all waiting continuations
        for continuation in continuations {
            continuation.resume(returning: value)
        }
        continuations.removeAll()
    }

    func get() async -> Value {
        // If a current value exists, return it immediately
        if let value = latestValue {
            return value
        }

        // Otherwise: suspend and wait for the next value
        return await withCheckedContinuation { (continuation: CheckedContinuation<Value, Never>) in
            continuations.append(continuation)
        }
    }
}

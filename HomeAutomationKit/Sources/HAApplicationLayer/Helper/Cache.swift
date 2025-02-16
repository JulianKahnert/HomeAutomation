//
//  Cache.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 16.02.25.
//

import Foundation

actor Cache<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let expirationDate: Date
    }

    private var wrapped: [Key: Entry]
    private let entryLifetime: Duration

    init(entryLifetime: Duration) {
        self.wrapped = [:]
        self.entryLifetime = entryLifetime

    }

    func insert(_ value: Value, forKey key: Key) {
        let date = Date().addingTimeInterval(entryLifetime.timeInterval)
        let entry = Entry(value: value, expirationDate: date)
        wrapped[key] = entry
    }

    func value(forKey key: Key) -> Value? {
        guard let entry = wrapped[key] else {
            return nil
        }

        guard Date() < entry.expirationDate else {
            // Discard values that have expired
            removeValue(forKey: key)
            return nil
        }

        return entry.value
    }

    func removeValue(forKey key: Key) {
        wrapped.removeValue(forKey: key)
    }
}

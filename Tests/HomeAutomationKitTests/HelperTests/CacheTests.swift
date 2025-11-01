//
//  CacheTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 01.11.25.
//

import Foundation
@testable import Adapter
import Testing

struct CacheTests {

    @Test("Insert and retrieve value")
    func insertAndRetrieve() {
        let cache = Cache<String, Int>()

        cache.insert(42, forKey: "answer")

        let value = cache.value(forKey: "answer")
        #expect(value == 42)
    }

    @Test("Return nil for non-existent key")
    func nonExistentKey() {
        let cache = Cache<String, Int>()

        let value = cache.value(forKey: "missing")
        #expect(value == nil)
    }

    @Test("Subscript insert and retrieve")
    func subscriptAccess() {
        let cache = Cache<String, String>()

        cache["greeting"] = "Hello"

        #expect(cache["greeting"] == "Hello")
    }

    @Test("Subscript set nil removes value")
    func subscriptRemoval() {
        let cache = Cache<String, String>()

        cache["key"] = "value"
        #expect(cache["key"] == "value")

        cache["key"] = nil
        #expect(cache["key"] == nil)
    }

    @Test("Remove value")
    func removeValue() {
        let cache = Cache<String, Int>()

        cache.insert(100, forKey: "score")
        #expect(cache.value(forKey: "score") == 100)

        cache.removeValue(forKey: "score")
        #expect(cache.value(forKey: "score") == nil)
    }

    @Test("Value expires after lifetime")
    func expiration() {
        var currentDate = Date()
        let dateProvider: () -> Date = { currentDate }

        let cache = Cache<String, String>(
            dateProvider: dateProvider,
            entryLifetime: 60 // 60 seconds
        )

        cache.insert("fresh", forKey: "data")

        // Value should exist immediately
        #expect(cache.value(forKey: "data") == "fresh")

        // Advance time by 30 seconds - should still exist
        currentDate = currentDate.addingTimeInterval(30)
        #expect(cache.value(forKey: "data") == "fresh")

        // Advance time by another 31 seconds (total 61) - should be expired
        currentDate = currentDate.addingTimeInterval(31)
        #expect(cache.value(forKey: "data") == nil)
    }

    @Test("Multiple keys are independent")
    func multipleKeys() {
        let cache = Cache<String, Int>()

        cache.insert(1, forKey: "one")
        cache.insert(2, forKey: "two")
        cache.insert(3, forKey: "three")

        #expect(cache.value(forKey: "one") == 1)
        #expect(cache.value(forKey: "two") == 2)
        #expect(cache.value(forKey: "three") == 3)

        cache.removeValue(forKey: "two")

        #expect(cache.value(forKey: "one") == 1)
        #expect(cache.value(forKey: "two") == nil)
        #expect(cache.value(forKey: "three") == 3)
    }

    @Test("Updating existing key")
    func updateExistingKey() {
        let cache = Cache<String, Int>()

        cache.insert(10, forKey: "count")
        #expect(cache.value(forKey: "count") == 10)

        cache.insert(20, forKey: "count")
        #expect(cache.value(forKey: "count") == 20)
    }

    @Test("Custom entry lifetime")
    func customLifetime() {
        var currentDate = Date()
        let dateProvider: () -> Date = { currentDate }

        let cache = Cache<String, String>(
            dateProvider: dateProvider,
            entryLifetime: 120 // 2 minutes
        )

        cache.insert("data", forKey: "key")

        // Should exist after 1 minute
        currentDate = currentDate.addingTimeInterval(60)
        #expect(cache.value(forKey: "key") == "data")

        // Should still exist after 1 minute 59 seconds
        currentDate = currentDate.addingTimeInterval(59)
        #expect(cache.value(forKey: "key") == "data")

        // Should be expired after 2 minutes 1 second
        currentDate = currentDate.addingTimeInterval(2)
        #expect(cache.value(forKey: "key") == nil)
    }
}

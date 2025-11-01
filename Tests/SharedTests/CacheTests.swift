//
//  CacheTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 01.11.25.
//

import Foundation
@testable import Shared
import Testing

struct CacheTests {

    @Test("Insert and retrieve value")
    func insertAndRetrieve() async {
        let cache = Cache<String, Int>()

        await cache.insert(42, forKey: "answer")

        let value = await cache.value(forKey: "answer")
        #expect(value == 42)
    }

    @Test("Return nil for non-existent key")
    func nonExistentKey() async {
        let cache = Cache<String, Int>()

        let value = await cache.value(forKey: "missing")
        #expect(value == nil)
    }

    @Test("Subscript insert and retrieve")
    func subscriptAccess() async {
        let cache = Cache<String, String>()

        await cache.insert("Hello", forKey: "greeting")

        #expect(await cache.value(forKey: "greeting") == "Hello")
    }

    @Test("Subscript set nil removes value")
    func subscriptRemoval() async {
        let cache = Cache<String, String>()

        await cache.insert("value", forKey: "key")
        #expect(await cache.value(forKey: "key") == "value")

        await cache.removeValue(forKey: "key")
        #expect(await cache.value(forKey: "key") == nil)
    }

    @Test("Remove value")
    func removeValue() async {
        let cache = Cache<String, Int>()

        await cache.insert(100, forKey: "score")
        #expect(await cache.value(forKey: "score") == 100)

        await cache.removeValue(forKey: "score")
        #expect(await cache.value(forKey: "score") == nil)
    }

    @Test("Value expires after lifetime")
    func expiration() async {
        final class DateHolder: @unchecked Sendable {
            var currentDate = Date()
        }
        let holder = DateHolder()
        let dateProvider: @Sendable () -> Date = { holder.currentDate }

        let cache = Cache<String, String>(
            dateProvider: dateProvider,
            entryLifetime: 60 // 60 seconds
        )

        await cache.insert("fresh", forKey: "data")

        // Value should exist immediately
        #expect(await cache.value(forKey: "data") == "fresh")

        // Advance time by 30 seconds - should still exist
        holder.currentDate = holder.currentDate.addingTimeInterval(30)
        #expect(await cache.value(forKey: "data") == "fresh")

        // Advance time by another 31 seconds (total 61) - should be expired
        holder.currentDate = holder.currentDate.addingTimeInterval(31)
        #expect(await cache.value(forKey: "data") == nil)
    }

    @Test("Multiple keys are independent")
    func multipleKeys() async {
        let cache = Cache<String, Int>()

        await cache.insert(1, forKey: "one")
        await cache.insert(2, forKey: "two")
        await cache.insert(3, forKey: "three")

        #expect(await cache.value(forKey: "one") == 1)
        #expect(await cache.value(forKey: "two") == 2)
        #expect(await cache.value(forKey: "three") == 3)

        await cache.removeValue(forKey: "two")

        #expect(await cache.value(forKey: "one") == 1)
        #expect(await cache.value(forKey: "two") == nil)
        #expect(await cache.value(forKey: "three") == 3)
    }

    @Test("Updating existing key")
    func updateExistingKey() async {
        let cache = Cache<String, Int>()

        await cache.insert(10, forKey: "count")
        #expect(await cache.value(forKey: "count") == 10)

        await cache.insert(20, forKey: "count")
        #expect(await cache.value(forKey: "count") == 20)
    }

    @Test("Custom entry lifetime")
    func customLifetime() async {
        final class DateHolder: @unchecked Sendable {
            var currentDate = Date()
        }
        let holder = DateHolder()
        let dateProvider: @Sendable () -> Date = { holder.currentDate }

        let cache = Cache<String, String>(
            dateProvider: dateProvider,
            entryLifetime: 120 // 2 minutes
        )

        await cache.insert("data", forKey: "key")

        // Should exist after 1 minute
        holder.currentDate = holder.currentDate.addingTimeInterval(60)
        #expect(await cache.value(forKey: "key") == "data")

        // Should still exist after 1 minute 59 seconds
        holder.currentDate = holder.currentDate.addingTimeInterval(59)
        #expect(await cache.value(forKey: "key") == "data")

        // Should be expired after 2 minutes 1 second
        holder.currentDate = holder.currentDate.addingTimeInterval(2)
        #expect(await cache.value(forKey: "key") == nil)
    }
}

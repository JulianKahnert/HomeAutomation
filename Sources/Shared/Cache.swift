//
//  CommandCache.swift
//
//
//  Created by Julian Kahnert on 01.11.25.
//

import Foundation

/// Generic cache with time-based expiration
/// Based on: https://www.swiftbysundell.com/articles/caching-in-swift/
public actor Cache<Key: Hashable & Sendable, Value: Sendable> {
    private let wrapped = NSCache<WrappedKey, Entry>()
    private let dateProvider: @Sendable () -> Date
    private let entryLifetime: TimeInterval?

    /// Convenience initializer that accepts Duration
    public init(dateProvider: @escaping @Sendable () -> Date = Date.init,
         entryLifetime: Duration? = nil) {
        self.dateProvider = dateProvider
        self.entryLifetime = entryLifetime?.timeInterval
    }

    public func insert(_ value: Value, forKey key: Key) {
        let entry: Entry
        if let entryLifetime = entryLifetime {
            let date = dateProvider().addingTimeInterval(entryLifetime)
            entry = Entry(key: key, value: value, expirationDate: date)
        } else {
            entry = Entry(key: key, value: value, expirationDate: nil)
        }
        wrapped.setObject(entry, forKey: WrappedKey(key))
    }

    public func value(forKey key: Key) -> Value? {
        guard let entry = wrapped.object(forKey: WrappedKey(key)) else {
            return nil
        }

        if let expirationDate = entry.expirationDate {
            if dateProvider() < expirationDate {
                return entry.value
            } else {
                // Discard values that have expired
                removeValue(forKey: key)
                return nil
            }
        } else {
            return entry.value
        }
    }

    public func removeValue(forKey key: Key) {
        wrapped.removeObject(forKey: WrappedKey(key))
    }

    public subscript(key: Key) -> Value? {
        get { return value(forKey: key) }
        set {
            guard let value = newValue else {
                // If nil was assigned using our subscript,
                // then we remove any value for that key:
                removeValue(forKey: key)
                return
            }

            insert(value, forKey: key)
        }
    }
}

// MARK: - Helper Types

private extension Cache {
    final class WrappedKey: NSObject {
        let key: Key

        init(_ key: Key) { self.key = key }

        override var hash: Int { return key.hashValue }

        override func isEqual(_ object: Any?) -> Bool {
            guard let value = object as? WrappedKey else {
                return false
            }

            return value.key == key
        }
    }
}

private extension Cache {
    final class Entry {
        let key: Key
        let value: Value
        let expirationDate: Date?

        init(key: Key, value: Value, expirationDate: Date?) {
            self.key = key
            self.value = value
            self.expirationDate = expirationDate
        }
    }
}

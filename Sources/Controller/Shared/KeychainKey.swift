//
//  KeychainKey.swift
//  ControllerFeatures
//
//  Custom SharedKey implementation backed by the iOS/macOS Keychain.
//  Survives app reinstalls and stores credentials securely.
//

#if canImport(Security)
import Foundation
import Shared
import Sharing

// MARK: - SharedReaderKey Extension

extension SharedReaderKey {
    /// Creates a shared key that persists a string value in the Keychain.
    public static func keychain(
        _ key: String
    ) -> Self where Self == KeychainKey<String> {
        KeychainKey(key: key)
    }

    /// Creates a shared key that persists a URL value in the Keychain.
    public static func keychain(
        _ key: String
    ) -> Self where Self == KeychainKey<URL> {
        KeychainKey(key: key)
    }
}

// MARK: - KeychainKey

public struct KeychainKey<Value: Sendable>: SharedKey {
    private let key: String
    private let helper: KeychainHelper
    private let encode: @Sendable (Value) -> String?
    private let decode: @Sendable (String) -> Value?

    public var id: KeychainKeyID {
        KeychainKeyID(key: key)
    }

    public func load(context: LoadContext<Value>, continuation: LoadContinuation<Value>) {
        let value: Value?
        if let raw = helper.readString(key) {
            value = decode(raw)
        } else {
            value = nil
        }
        continuation.resume(with: .success(value))
    }

    public func subscribe(
        context: LoadContext<Value>,
        subscriber: SharedSubscriber<Value>
    ) -> SharedSubscription {
        SharedSubscription {}
    }

    public func save(_ value: Value, context: SaveContext, continuation: SaveContinuation) {
        if let raw = encode(value) {
            helper.writeString(key, value: raw)
        }
        continuation.resume()
    }
}

// MARK: - Initializers

extension KeychainKey where Value == String {
    init(key: String) {
        self.key = key
        self.helper = KeychainHelper()
        self.encode = { $0 }
        self.decode = { $0 }
    }
}

extension KeychainKey where Value == URL {
    init(key: String) {
        self.key = key
        self.helper = KeychainHelper()
        self.encode = { $0.absoluteString }
        self.decode = { URL(string: $0) }
    }
}

// MARK: - ID & Description

public struct KeychainKeyID: Hashable {
    fileprivate let key: String
}

extension KeychainKey: CustomStringConvertible {
    public var description: String {
        ".keychain(\(String(reflecting: key)))"
    }
}
#endif

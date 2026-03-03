//
//  KeychainKey.swift
//  ControllerFeatures
//
//  Custom SharedKey implementation backed by the iOS/macOS Keychain.
//  Survives app reinstalls and stores credentials securely.
//

#if canImport(Security)
import Foundation
import Security
import Sharing

// MARK: - SharedReaderKey Extension

extension SharedReaderKey {
    /// Creates a shared key that persists a string value in the Keychain.
    ///
    /// - Parameters:
    ///   - key: The account name used to identify the Keychain item.
    ///   - service: The service name for the Keychain item. Defaults to the app's bundle identifier.
    /// - Returns: A Keychain-backed shared key.
    public static func keychain(
        _ key: String,
        service: String? = nil
    ) -> Self where Self == KeychainKey<String> {
        KeychainKey(key: key, service: service)
    }

    /// Creates a shared key that persists a URL value in the Keychain.
    ///
    /// - Parameters:
    ///   - key: The account name used to identify the Keychain item.
    ///   - service: The service name for the Keychain item. Defaults to the app's bundle identifier.
    /// - Returns: A Keychain-backed shared key.
    public static func keychain(
        _ key: String,
        service: String? = nil
    ) -> Self where Self == KeychainKey<URL> {
        KeychainKey(key: key, service: service)
    }
}

// MARK: - KeychainKey

public struct KeychainKey<Value: Sendable>: SharedKey {
    private let key: String
    private let service: String
    private let encode: @Sendable (Value) -> Data?
    private let decode: @Sendable (Data) -> Value?

    public var id: KeychainKeyID {
        KeychainKeyID(key: key, service: service)
    }

    public func load(context: LoadContext<Value>, continuation: LoadContinuation<Value>) {
        let value = readFromKeychain()
        continuation.resume(with: .success(value))
    }

    public func subscribe(
        context: LoadContext<Value>,
        subscriber: SharedSubscriber<Value>
    ) -> SharedSubscription {
        // Keychain has no built-in observation mechanism.
        // Values are always loaded fresh on access, so no subscription needed.
        SharedSubscription {}
    }

    public func save(_ value: Value, context: SaveContext, continuation: SaveContinuation) {
        writeToKeychain(value)
        continuation.resume()
    }
}

// MARK: - Initializers

extension KeychainKey where Value == String {
    init(key: String, service: String?) {
        self.key = key
        self.service = service ?? (Bundle.main.bundleIdentifier ?? "HomeAutomation")
        self.encode = { $0.data(using: .utf8) }
        self.decode = { String(data: $0, encoding: .utf8) }
    }
}

extension KeychainKey where Value == URL {
    init(key: String, service: String?) {
        self.key = key
        self.service = service ?? (Bundle.main.bundleIdentifier ?? "HomeAutomation")
        self.encode = { $0.absoluteString.data(using: .utf8) }
        self.decode = { String(data: $0, encoding: .utf8).flatMap(URL.init(string:)) }
    }
}

// MARK: - Keychain Operations

extension KeychainKey {
    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
    }

    private func readFromKeychain() -> Value? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return decode(data)
    }

    private func writeToKeychain(_ value: Value) {
        guard let data = encode(value) else { return }

        // Delete and re-add to ensure the accessibility attribute is up-to-date.
        // SecItemUpdate cannot change kSecAttrAccessible on existing items.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        var query = baseQuery()
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }
}

// MARK: - ID & Description

public struct KeychainKeyID: Hashable {
    fileprivate let key: String
    fileprivate let service: String
}

extension KeychainKey: CustomStringConvertible {
    public var description: String {
        ".keychain(\(String(reflecting: key)))"
    }
}
#endif

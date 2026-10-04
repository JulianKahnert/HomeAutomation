//
//  AdapterCredentialStore.swift
//  Adapter
//

#if canImport(SwiftUI)
import Foundation
import Logging
import Observation
import Shared

/// Keychain-backed storage for the adapter's server bearer token.
///
/// The token used to live in `UserDefaults` (`@AppStorage("ServerAuthToken")`), i.e. in a
/// plaintext plist inside the app container that ends up in every backup. It is the single
/// credential that also grants full access to the server's HTTP API, so it belongs in the
/// keychain — the same place the Controller app and `home` CLI keep theirs. Existing installs
/// are migrated on first launch and the plaintext copy is removed.
@MainActor
@Observable
public final class AdapterCredentialStore {
    private static let log = Logger(label: "AdapterCredentialStore")
    static let keychainAccount = "adapterServerAuthToken"
    static let legacyUserDefaultsKey = "ServerAuthToken"

    /// The current bearer token; empty when none is configured.
    public private(set) var authToken: String

    public init(userDefaults: UserDefaults = .standard) {
        if let stored = KeychainHelper.readString(Self.keychainAccount) {
            authToken = stored
        } else if let legacy = userDefaults.string(forKey: Self.legacyUserDefaultsKey), !legacy.isEmpty {
            authToken = legacy
            if KeychainHelper.writeString(Self.keychainAccount, value: legacy) {
                Self.log.notice("migrated server auth token from UserDefaults to the keychain")
            } else {
                Self.log.error("failed to migrate server auth token to the keychain - it will have to be re-entered after the next restart")
            }
        } else {
            authToken = ""
        }
        // Never leave a plaintext copy behind, whether or not the keychain write succeeded.
        userDefaults.removeObject(forKey: Self.legacyUserDefaultsKey)
    }

    /// Persists `token` in the keychain and publishes it to observers (the app restarts the
    /// connection whenever it changes).
    public func update(authToken token: String) {
        if !KeychainHelper.writeString(Self.keychainAccount, value: token) {
            Self.log.error("failed to store server auth token in the keychain")
        }
        authToken = token
    }
}
#endif

#if canImport(Security)
import Foundation
import Security

public struct KeychainHelper: Sendable {
    private let service: String

    public init(service: String = Bundle.main.bundleIdentifier ?? "de.juliankahnert.HomeAutomation") {
        self.service = service
    }

    public func readString(_ account: String) -> String? {
        guard let data = readData(account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func writeString(_ account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        writeData(account, data: data)
    }

    public func readURL(_ account: String) -> URL? {
        guard let string = readString(account) else { return nil }
        return URL(string: string)
    }

    public func writeURL(_ account: String, value: URL) {
        writeString(account, value: value.absoluteString)
    }

    // MARK: - Private

    private func readData(_ account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return data
    }

    private func writeData(_ account: String, data: Data) {
        // Delete first to ensure kSecAttrAccessible is up-to-date
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }
}
#endif

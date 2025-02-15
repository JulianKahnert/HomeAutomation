//
//  KeychainHelper.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 23.08.24.
//
#warning("TODO: remove this")
// import Foundation
//
// #warning("TODO: remove this and use env vars on server instead")
// public enum KeychainHelper {
//    public static func save(secret: String, for server: String) {
//        let secretData = secret.data(using: String.Encoding.utf8)!
//        let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
//                                    kSecAttrServer as String: server,
//                                    kSecValueData as String: secretData,
//                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
//                                    kSecAttrSynchronizable as String: true]
//
//        let status = SecItemAdd(query as CFDictionary, nil)
//
//        if status != errSecSuccess {
//            // Print out the error
//            print("Error: \(status)")
//            assertionFailure()
//        }
//    }
//
//    public static func readSecret(for server: String) -> String? {
//        let query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
//                                    kSecAttrServer as String: server,
//                                    kSecMatchLimit as String: kSecMatchLimitOne,
//                                    kSecReturnAttributes as String: true,
//                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
//                                    kSecAttrSynchronizable as String: true,
//                                    kSecReturnData as String: true]
//
//        var item: CFTypeRef?
//        _ = SecItemCopyMatching(query as CFDictionary, &item)
//
//        guard let existingItem = item as? [String: Any],
//            let passwordData = existingItem[kSecValueData as String] as? Data,
//            let accessToken = String(data: passwordData, encoding: String.Encoding.utf8) else { return nil }
//
//        return accessToken
//    }
// }

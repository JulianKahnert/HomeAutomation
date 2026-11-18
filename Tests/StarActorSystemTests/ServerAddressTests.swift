//
//  ServerAddressTests.swift
//  HomeAutomationKit
//

import Foundation
@testable import StarActorSystem
import Testing

struct ServerAddressTests {

    @Test("Legacy raw value without TLS marker still parses and stays plaintext")
    func legacyRawValue() throws {
        let address = try #require(ServerAddress(rawValue: "192.168.1.3###8080"))
        #expect(address.host == "192.168.1.3")
        #expect(address.port == 8080)
        #expect(!address.useTLS)
        #expect(address.scheme == "ws")
        #expect(address.rawValue == "192.168.1.3###8080")
        #expect(address.webSocketURL(path: "/adapter/v1")?.absoluteString == "ws://192.168.1.3:8080/adapter/v1")
    }

    @Test("TLS raw value round-trips and produces a wss URL")
    func tlsRawValue() throws {
        let original = ServerAddress(host: "ol.example.org", port: 443, useTLS: true)
        #expect(original.rawValue == "ol.example.org###443###tls")
        let parsed = try #require(ServerAddress(rawValue: original.rawValue))
        #expect(parsed == original)
        #expect(parsed.description == "wss://ol.example.org:443/")
        #expect(parsed.webSocketURL(path: "/adapter/v1")?.absoluteString == "wss://ol.example.org:443/adapter/v1")
    }

    @Test("Old cluster port 8888 is migrated to 8080")
    func portMigration() throws {
        let address = try #require(ServerAddress(rawValue: "localhost###8888"))
        #expect(address.port == 8080)
    }

    @Test("Decoding JSON without useTLS defaults to plaintext")
    func decodingWithoutTLSKey() throws {
        let data = Data(#"{"host":"localhost","port":8080}"#.utf8)
        let address = try JSONDecoder().decode(ServerAddress.self, from: data)
        #expect(address == ServerAddress(host: "localhost", port: 8080))
        let roundTrip = try JSONDecoder().decode(ServerAddress.self, from: JSONEncoder().encode(ServerAddress(host: "h", port: 1, useTLS: true)))
        #expect(roundTrip.useTLS)
    }
}

//
//  ServerAddress.swift
//  StarActorSystem
//

import Foundation
import Logging

/// The adapter's persisted server endpoint.
///
/// The `RawRepresentable` encoding ("host###port") is kept identical to the previous
/// `CustomActorSystem.Address` so stored `@AppStorage` values survive the migration.
/// A third component ("host###port###tls") selects an encrypted `wss://` connection, so
/// the bearer token and all HomeKit traffic never cross the network in clear text.
public struct ServerAddress: Codable, Equatable, CustomStringConvertible, Sendable {
    public let host: String
    public let port: Int
    public let useTLS: Bool

    public init(host: String, port: Int, useTLS: Bool = false) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
    }

    /// `wss` when TLS is enabled, `ws` otherwise.
    public var scheme: String {
        useTLS ? "wss" : "ws"
    }

    /// The WebSocket URL for `path` (e.g. `/adapter/v1`) on this server.
    public func webSocketURL(path: String) -> URL? {
        URL(string: "\(scheme)://\(host):\(port)\(path)")
    }

    public var description: String {
        "\(scheme)://\(host):\(port)/"
    }

    // MARK: - Codable
    //
    // Explicit on purpose: `RawRepresentable` would otherwise supply a single-string encoding,
    // and the keyed decoder tolerates values persisted before `useTLS` existed.

    private enum CodingKeys: String, CodingKey {
        case host, port, useTLS
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.host = try container.decode(String.self, forKey: .host)
        self.port = try container.decode(Int.self, forKey: .port)
        self.useTLS = try container.decodeIfPresent(Bool.self, forKey: .useTLS) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host, forKey: .host)
        try container.encode(port, forKey: .port)
        try container.encode(useTLS, forKey: .useTLS)
    }
}

extension ServerAddress: RawRepresentable {
    private static let separator = "###"
    private static let tlsMarker = "tls"
    private static let logger = Logger(label: "StarActorSystem.ServerAddress")
    public var rawValue: String {
        let base = "\(host)\(Self.separator)\(port)"
        return useTLS ? "\(base)\(Self.separator)\(Self.tlsMarker)" : base
    }

    public init?(rawValue: String) {
        let parts = rawValue.components(separatedBy: Self.separator)

        guard parts.count == 2 || parts.count == 3,
              let rawHost = parts.first,
              var port = Int(parts[1]) else {
            assertionFailure("Failed to parse address \(rawValue)")
            return nil
        }
        let useTLS = parts.count == 3 && parts[2] == Self.tlsMarker
        guard parts.count == 2 || useTLS else {
            assertionFailure("Failed to parse address \(rawValue)")
            return nil
        }

        // Migration: 8888 was the old DistributedCluster port, which no longer
        // exists — the WebSocket transport lives on the HTTP port 8080.
        if port == 8888 {
            Self.logger.notice("migrating stored server address from old cluster port 8888 to 8080")
            port = 8080
        }

        self.init(host: rawHost, port: port, useTLS: useTLS)
    }
}

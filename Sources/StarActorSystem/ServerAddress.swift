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
public struct ServerAddress: Codable, Equatable, CustomStringConvertible, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    public var description: String {
        "ws://\(host):\(port)/"
    }
}

extension ServerAddress: RawRepresentable {
    private static let separator = "###"
    private static let logger = Logger(label: "StarActorSystem.ServerAddress")
    public var rawValue: String {
        "\(host)\(Self.separator)\(port)"
    }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: Self.separator)

        guard parts.count == 2,
              let rawHost = parts.first,
              let rawPort = parts.last,
              var port = Int(rawPort) else {
            assertionFailure("Failed to parse address \(rawValue)")
            return nil
        }

        // Migration: 8888 was the old DistributedCluster port, which no longer
        // exists — the WebSocket transport lives on the HTTP port 8080.
        if port == 8888 {
            Self.logger.notice("migrating stored server address from old cluster port 8888 to 8080")
            port = 8080
        }

        self.init(host: String(rawHost), port: port)
    }
}

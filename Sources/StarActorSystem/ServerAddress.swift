//
//  ServerAddress.swift
//  StarActorSystem
//

import Foundation

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
    public var rawValue: String {
        "\(host)\(Self.separator)\(port)"
    }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: Self.separator)

        guard parts.count == 2,
              let rawHost = parts.first,
              let rawPort = parts.last,
              let port = Int(rawPort) else {
            assertionFailure("Failed to parse address \(rawValue)")
            return nil
        }

        self.init(host: String(rawHost), port: port)
    }
}

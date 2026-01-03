//
//  CustomActorSystem+Address.swift
//
//
//  Created by Julian Kahnert on 06.02.25.
//

import Foundation

extension CustomActorSystem {
    public struct Address: Codable, Equatable, CustomStringConvertible, Sendable {
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
}

extension CustomActorSystem.Address: RawRepresentable {
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

//
//  StarActorID.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 26.07.26.
//

import Foundation

/// Identity of a distributed actor in the 2-node star topology.
///
/// Well-known IDs are fixed strings so both nodes can resolve their peer's
/// actors without any discovery mechanism.
public struct StarActorID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let id: String

    public init(_ id: String) {
        self.id = id
    }

    /// Receiver for home events — lives on the server.
    public static let homeEventReceiver = StarActorID("home-event-receiver")
    /// Receiver for HomeKit commands — lives on the adapter.
    public static let homeKitCommandReceiver = StarActorID("homekit-command-receiver")

    /// A random ID for actors created without a well-known identity.
    static func random() -> StarActorID {
        StarActorID(UUID().uuidString)
    }

    public var description: String {
        id
    }
}

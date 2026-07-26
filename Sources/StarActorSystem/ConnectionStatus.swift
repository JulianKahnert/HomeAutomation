//
//  ConnectionStatus.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 26.07.26.
//

/// Connection status of the star link between server and adapter.
///
/// - `connecting`: initial state, or no socket is attached.
/// - `up`: a socket is attached and the hello handshake completed.
/// - `error`: a socket that was `.up` detached.
public enum ConnectionStatus: String, Codable, Sendable {
    // swiftlint:disable:next identifier_name
    case up
    case connecting
    case error

    /// True when this transition into `.up` comes from a not-up state (including the very first one).
    public func isReconnect(from previous: ConnectionStatus?) -> Bool {
        self == .up && previous != .up
    }
}

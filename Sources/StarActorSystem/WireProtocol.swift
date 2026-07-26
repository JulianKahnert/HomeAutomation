//
//  WireProtocol.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 26.07.26.
//
//  Wire protocol of the star actor system. JSON via JSONEncoder/JSONDecoder.
//  EVOLUTION RULE: additive-only — never rename or remove fields/cases;
//  golden tests in StarActorSystemTests freeze the encoded shape.
//

import Foundation

/// A single transport connection the actor system sends frames over.
public protocol WireConnection: Sendable {
    func send(_ data: Data) async throws
    func close() async
}

/// Top-level frame on the wire.
enum WireEnvelope: Codable, Sendable {
    /// FIRST frame in both directions after connect; version mismatch → close.
    case hello(Hello)
    case call(RemoteCallEnvelope)
    case reply(ReplyEnvelope)
}

struct Hello: Codable, Sendable {
    /// Current protocol version — see ``StarActorSystem/protocolVersion``.
    let protocolVersion: Int
}

struct RemoteCallEnvelope: Codable, Sendable {
    let callID: UUID
    let recipient: StarActorID
    /// `RemoteCallTarget.identifier` (mangled thunk name — module name is part of the contract).
    let target: String
    /// Each argument JSON-encoded separately.
    let arguments: [Data]
}

struct ReplyEnvelope: Codable, Sendable {
    let callID: UUID
    /// JSON-encoded return value; nil for Void or error.
    let result: Data?
    /// nil on success.
    let errorMessage: String?
}

/// Error thrown for any remote-call failure (not connected, timeout, remote error, decode failure).
public struct StarRemoteCallError: Error, Codable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

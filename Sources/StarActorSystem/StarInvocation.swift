//
//  StarInvocation.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 26.07.26.
//

import Distributed
import Foundation
import Logging

/// Records the arguments of an outbound remote call — each argument is JSON-encoded separately.
public struct StarInvocationEncoder: DistributedTargetInvocationEncoder {
    public typealias SerializationRequirement = any Codable

    private(set) var arguments: [Data] = []

    public mutating func recordGenericSubstitution<T>(_ type: T.Type) throws {
        throw StarRemoteCallError(message: "generic distributed methods unsupported")
    }

    public mutating func recordArgument<Value: Codable>(_ argument: RemoteCallArgument<Value>) throws {
        arguments.append(try JSONEncoder().encode(argument.value))
    }

    public mutating func recordReturnType<R: Codable>(_ type: R.Type) throws {
        // Return type is recovered from the thunk on the executing side.
    }

    public mutating func recordErrorType<E: Error>(_ type: E.Type) throws {
        // Errors travel as plain strings — no typed error round-trip.
    }

    public mutating func doneRecording() throws {
        // Nothing to finalize.
    }
}

/// Decodes the arguments of an inbound remote call.
public struct StarInvocationDecoder: DistributedTargetInvocationDecoder {
    public typealias SerializationRequirement = any Codable

    private let arguments: [Data]
    private var index = 0

    init(arguments: [Data]) {
        self.arguments = arguments
    }

    public mutating func decodeGenericSubstitutions() throws -> [any Any.Type] {
        []
    }

    public mutating func decodeNextArgument<Argument: Codable>() throws -> Argument {
        guard index < arguments.count else {
            throw StarRemoteCallError(message: "missing argument at index \(index)")
        }
        defer { index += 1 }
        return try JSONDecoder().decode(Argument.self, from: arguments[index])
    }

    public mutating func decodeErrorType() throws -> (any Any.Type)? {
        nil
    }

    public mutating func decodeReturnType() throws -> (any Any.Type)? {
        nil
    }
}

/// Sends the reply envelope for an executed inbound call back over the connection.
public struct StarResultHandler: DistributedTargetInvocationResultHandler {
    public typealias SerializationRequirement = any Codable

    let callID: UUID
    let connection: any WireConnection
    let logger: Logger

    public func onReturn<Success: Codable>(value: Success) async throws {
        let result = try JSONEncoder().encode(value)
        try await sendReply(ReplyEnvelope(callID: callID, result: result, errorMessage: nil))
    }

    public func onReturnVoid() async throws {
        try await sendReply(ReplyEnvelope(callID: callID, result: nil, errorMessage: nil))
    }

    public func onThrow<Err: Error>(error: Err) async throws {
        try await sendReply(ReplyEnvelope(callID: callID, result: nil, errorMessage: String(describing: error)))
    }

    private func sendReply(_ reply: ReplyEnvelope) async throws {
        logger.debug("sending reply", metadata: [
            "callID": "\(reply.callID)",
            "error": "\(reply.errorMessage ?? "none")"
        ])
        try await connection.send(try JSONEncoder().encode(WireEnvelope.reply(reply)))
    }
}

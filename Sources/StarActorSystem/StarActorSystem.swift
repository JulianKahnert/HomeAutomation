//
//  StarActorSystem.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 26.07.26.
//

import Distributed
import Foundation
import Logging

/// A minimal `DistributedActorSystem` for a 2-node star topology (server ↔ adapter)
/// over a single WebSocket-like `WireConnection`.
///
/// The `DistributedActorSystem` protocol requires `assignID`/`actorReady`/`resignID`/
/// `resolve` to be synchronous, so mutable state is guarded by an `NSLock`
/// (class + lock pattern) and the type is `@unchecked Sendable`. The lock is
/// never held across a suspension point.
public final class StarActorSystem: DistributedActorSystem, @unchecked Sendable {
    public typealias ActorID = StarActorID
    public typealias SerializationRequirement = any Codable
    public typealias InvocationEncoder = StarInvocationEncoder
    public typealias InvocationDecoder = StarInvocationDecoder
    public typealias ResultHandler = StarResultHandler

    /// Current wire protocol version. Bump only for incompatible changes (additive-only rule).
    static let protocolVersion = 1

    private let name: String
    private let remoteCallTimeout: Duration
    private let logger: Logger
    private let pendingCalls = PendingCalls()

    // MARK: - Lock-guarded state

    private let lock = NSLock()
    private var registry: [StarActorID: any DistributedActor] = [:]
    private var reservedIDs: [StarActorID] = []
    private var connection: (any WireConnection)?
    private var helloSent = false
    private var helloReceived = false
    private var status: ConnectionStatus = .connecting
    private var statusSubscribers: [UUID: AsyncStream<ConnectionStatus>.Continuation] = [:]

    public init(name: String, remoteCallTimeout: Duration = .seconds(30), logger: Logger? = nil) {
        self.name = name
        self.remoteCallTimeout = remoteCallTimeout
        var systemLogger = logger ?? Logger(label: "StarActorSystem")
        systemLogger[metadataKey: "system"] = "\(name)"
        self.logger = systemLogger
    }

    // MARK: - Actor creation & resolution

    /// Create a local actor under a well-known ID.
    ///
    /// Reserves the ID so the runtime's `assignID` call (triggered by the factory's
    /// initializer) pops it. Not reentrant — called once per actor at boot.
    public func makeActor<Act: DistributedActor>(id: StarActorID, _ factory: () -> Act) -> Act where Act.ActorSystem == StarActorSystem {
        lock.withLock { reservedIDs.append(id) }
        return factory()
    }

    public func assignID<Act>(_ actorType: Act.Type) -> StarActorID where Act: DistributedActor, Act.ID == ActorID {
        lock.withLock { reservedIDs.popLast() ?? .random() }
    }

    public func actorReady<Act>(_ actor: Act) where Act: DistributedActor, Act.ID == ActorID {
        lock.withLock { registry[actor.id] = actor }
        logger.debug("actor ready", metadata: ["actorID": "\(actor.id)"])
    }

    public func resignID(_ id: StarActorID) {
        lock.withLock { _ = registry.removeValue(forKey: id) }
        logger.debug("actor resigned", metadata: ["actorID": "\(id)"])
    }

    /// Returns the local instance if one is registered under `id`; `nil` lets the
    /// runtime synthesize a remote proxy.
    public func resolve<Act>(id: StarActorID, as actorType: Act.Type) throws -> Act? where Act: DistributedActor, Act.ID == ActorID {
        guard let actor = lock.withLock({ registry[id] }) else { return nil }
        guard let typed = actor as? Act else {
            throw StarRemoteCallError(message: "actor \(id) is registered as \(type(of: actor)), not \(actorType)")
        }
        return typed
    }

    public func makeInvocationEncoder() -> StarInvocationEncoder {
        StarInvocationEncoder()
    }

    // MARK: - Outbound remote calls

    public func remoteCall<Act, Err, Res>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout StarInvocationEncoder,
        throwing: Err.Type,
        returning: Res.Type
    ) async throws -> Res where Act: DistributedActor, Act.ID == ActorID, Err: Error, Res: Codable {
        let reply = try await performRemoteCall(recipient: actor.id, target: target, arguments: invocation.arguments)
        guard let result = reply.result else {
            throw StarRemoteCallError(message: "remote call \(target.identifier) returned no result")
        }
        return try JSONDecoder().decode(Res.self, from: result)
    }

    public func remoteCallVoid<Act, Err>(
        on actor: Act,
        target: RemoteCallTarget,
        invocation: inout StarInvocationEncoder,
        throwing: Err.Type
    ) async throws where Act: DistributedActor, Act.ID == ActorID, Err: Error {
        _ = try await performRemoteCall(recipient: actor.id, target: target, arguments: invocation.arguments)
    }

    private func performRemoteCall(recipient: StarActorID, target: RemoteCallTarget, arguments: [Data]) async throws -> ReplyEnvelope {
        guard let connection = lock.withLock({ self.connection }) else {
            throw StarRemoteCallError(message: "not connected")
        }
        let envelope = RemoteCallEnvelope(callID: UUID(), recipient: recipient, target: target.identifier, arguments: arguments)
        logger.debug("outbound call", metadata: [
            "callID": "\(envelope.callID)",
            "target": "\(envelope.target)",
            "recipient": "\(envelope.recipient)"
        ])

        await pendingCalls.begin(envelope.callID)
        do {
            try await connection.send(try JSONEncoder().encode(WireEnvelope.call(envelope)))
        } catch {
            await pendingCalls.settle(envelope.callID, with: .failure(error))
        }
        let reply = try await pendingCalls.wait(for: envelope.callID, timeout: remoteCallTimeout)
        if let errorMessage = reply.errorMessage {
            logger.debug("remote call failed", metadata: ["callID": "\(envelope.callID)", "error": "\(errorMessage)"])
            throw StarRemoteCallError(message: errorMessage)
        }
        return reply
    }

    // MARK: - Transport side

    /// Attach a new connection. Latest-connection-wins: any previous connection is
    /// closed and its pending calls fail.
    public func attach(_ connection: any WireConnection) async {
        let previous: (any WireConnection)? = lock.withLock {
            let previous = self.connection
            self.connection = connection
            self.helloSent = false
            self.helloReceived = false
            return previous
        }
        if let previous {
            logger.info("connection replaced (latest-connection-wins), closing previous")
            await previous.close()
            await pendingCalls.failAll(StarRemoteCallError(message: "connection replaced"))
        }
        logger.info("connection attached")
        setStatus(.connecting)
    }

    /// The socket closed: fail all pending calls; status becomes `.error`
    /// (or stays `.connecting` if the connection never reached `.up`).
    public func detach() async {
        let wasUp: Bool = lock.withLock {
            let wasUp = status == .up
            connection = nil
            helloSent = false
            helloReceived = false
            return wasUp
        }
        await pendingCalls.failAll(StarRemoteCallError(message: "connection closed"))
        logger.info("connection detached", metadata: ["wasUp": "\(wasUp)"])
        setStatus(wasUp ? .error : .connecting)
    }

    /// Handle one inbound frame.
    public func receive(_ data: Data) async {
        let envelope: WireEnvelope
        do {
            envelope = try JSONDecoder().decode(WireEnvelope.self, from: data)
        } catch {
            logger.error("failed to decode inbound frame: \(error)")
            return
        }
        switch envelope {
        case .hello(let hello):
            await handleHello(hello)
        case .call(let call):
            logger.debug("inbound call", metadata: [
                "callID": "\(call.callID)",
                "target": "\(call.target)",
                "recipient": "\(call.recipient)"
            ])
            handleCall(call)
        case .reply(let reply):
            logger.debug("inbound reply", metadata: [
                "callID": "\(reply.callID)",
                "error": "\(reply.errorMessage ?? "none")"
            ])
            await pendingCalls.settle(reply.callID, with: .success(reply))
        }
    }

    public var isConnected: Bool {
        latestConnectionStatus == .up
    }

    public var latestConnectionStatus: ConnectionStatus {
        lock.withLock { status }
    }

    /// A stream seeded with the current status, then live updates. Multiple
    /// subscribers are supported; each buffers only the newest value.
    public func makeConnectionStatusStream() -> AsyncStream<ConnectionStatus> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: ConnectionStatus.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        let id = UUID()
        lock.withLock {
            continuation.yield(status)
            statusSubscribers[id] = continuation
        }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            self.lock.withLock { _ = self.statusSubscribers.removeValue(forKey: id) }
        }
        return stream
    }

    // MARK: - Hello handshake

    /// Send our hello frame over the current connection. Used by client
    /// transports right after `attach`, and internally to reply to a peer hello.
    func sendHello() async {
        guard let connection = lock.withLock({ helloSent = true; return self.connection }) else { return }
        do {
            try await connection.send(try JSONEncoder().encode(WireEnvelope.hello(Hello(protocolVersion: Self.protocolVersion))))
            logger.debug("hello sent", metadata: ["protocolVersion": "\(Self.protocolVersion)"])
        } catch {
            logger.error("failed to send hello: \(error)")
        }
    }

    private func handleHello(_ hello: Hello) async {
        guard hello.protocolVersion == Self.protocolVersion else {
            logger.error("protocol version mismatch: peer=\(hello.protocolVersion) local=\(Self.protocolVersion) — closing connection")
            let connection: (any WireConnection)? = lock.withLock {
                let connection = self.connection
                self.connection = nil
                self.helloSent = false
                self.helloReceived = false
                return connection
            }
            await connection?.close()
            await pendingCalls.failAll(StarRemoteCallError(message: "protocol version mismatch"))
            return
        }
        let shouldReply: Bool = lock.withLock {
            helloReceived = true
            return !helloSent
        }
        if shouldReply {
            // Server side: the client's transport sent the first hello; we answer.
            await sendHello()
        }
        let attached = lock.withLock { connection != nil }
        if attached {
            logger.info("hello handshake completed")
            setStatus(.up)
        }
    }

    // MARK: - Inbound call execution

    private func handleCall(_ envelope: RemoteCallEnvelope) {
        guard let connection = lock.withLock({ self.connection }) else {
            logger.error("inbound call \(envelope.callID) but no connection to reply on")
            return
        }
        let recipient = lock.withLock { registry[envelope.recipient] }
        // Each call runs in its own Task so concurrent calls interleave.
        Task { [logger] in
            guard let recipient else {
                logger.error("inbound call for unknown recipient", metadata: [
                    "callID": "\(envelope.callID)",
                    "recipient": "\(envelope.recipient)"
                ])
                await self.sendErrorReply(callID: envelope.callID, message: "unknown recipient \(envelope.recipient)", via: connection)
                return
            }
            await self.execute(envelope, on: recipient, via: connection)
        }
    }

    private func execute(_ envelope: RemoteCallEnvelope, on actor: some DistributedActor, via connection: any WireConnection) async {
        var decoder = StarInvocationDecoder(arguments: envelope.arguments)
        let handler = StarResultHandler(callID: envelope.callID, connection: connection, logger: logger)
        do {
            try await executeDistributedTarget(
                on: actor,
                target: RemoteCallTarget(envelope.target),
                invocationDecoder: &decoder,
                handler: handler
            )
        } catch {
            logger.error("failed to execute inbound call", metadata: [
                "callID": "\(envelope.callID)",
                "target": "\(envelope.target)",
                "error": "\(error)"
            ])
            await sendErrorReply(callID: envelope.callID, message: String(describing: error), via: connection)
        }
    }

    private func sendErrorReply(callID: UUID, message: String, via connection: any WireConnection) async {
        let reply = ReplyEnvelope(callID: callID, result: nil, errorMessage: message)
        do {
            try await connection.send(try JSONEncoder().encode(WireEnvelope.reply(reply)))
        } catch {
            logger.error("failed to send error reply for call \(callID): \(error)")
        }
    }

    // MARK: - Status

    private func setStatus(_ newStatus: ConnectionStatus) {
        let subscribers: [AsyncStream<ConnectionStatus>.Continuation]? = lock.withLock {
            guard status != newStatus else { return nil }
            status = newStatus
            return Array(statusSubscribers.values)
        }
        guard let subscribers else { return }
        logger.info("connection status changed", metadata: ["status": "\(newStatus.rawValue)"])
        for subscriber in subscribers {
            subscriber.yield(newStatus)
        }
    }
}

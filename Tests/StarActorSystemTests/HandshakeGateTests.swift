//
//  HandshakeGateTests.swift
//  HomeAutomationKit
//

import Foundation
@testable import StarActorSystem
import Testing

/// The peer's `hello` is the first frame and the only protocol-version gate, so no other
/// frame may be processed before it arrived.
struct HandshakeGateTests {

    private func callFrame() throws -> Data {
        let envelope = RemoteCallEnvelope(callID: UUID(), recipient: .greeter, target: "bogus", arguments: [])
        return try JSONEncoder().encode(WireEnvelope.call(envelope))
    }

    private func helloFrame() throws -> Data {
        try JSONEncoder().encode(WireEnvelope.hello(Hello(protocolVersion: StarActorSystem.protocolVersion)))
    }

    @Test("A call frame before hello closes the connection instead of executing")
    func callBeforeHelloClosesConnection() async throws {
        let server = StarActorSystem(name: "server")
        let greeter = server.makeActor(id: .greeter) { Greeter(actorSystem: server) }
        let connection = InMemoryWireConnection(blackhole: true)
        await server.attach(connection)

        await server.receive(try callFrame(), from: connection)

        #expect(connection.closed)
        #expect(!server.isConnected)
        #expect(server.latestConnectionStatus == .connecting)
        // No reply (not even an error reply) may have been produced for the rejected call.
        #expect(connection.sentFrames.isEmpty)

        // The dropped connection is stale now: a late hello on it must not bring the system up.
        await server.receive(try helloFrame(), from: connection)
        #expect(!server.isConnected)
        withExtendedLifetime(greeter) {}
    }

    @Test("A reply frame before hello closes the connection")
    func replyBeforeHelloClosesConnection() async throws {
        let system = StarActorSystem(name: "client")
        let connection = InMemoryWireConnection(blackhole: true)
        await system.attach(connection)

        let reply = ReplyEnvelope(callID: UUID(), result: nil, errorMessage: nil)
        await system.receive(try JSONEncoder().encode(WireEnvelope.reply(reply)), from: connection)

        #expect(connection.closed)
        #expect(!system.isConnected)
    }

    @Test("A call frame after a valid hello is still executed")
    func callAfterHelloIsExecuted() async throws {
        let server = StarActorSystem(name: "server")
        let greeter = server.makeActor(id: .greeter) { Greeter(actorSystem: server) }
        let connection = InMemoryWireConnection(blackhole: true)
        try await server.attachUp(connection)
        #expect(server.isConnected)

        await server.receive(try callFrame(), from: connection)

        // The bogus target yields an error reply - proof that the call reached execution.
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline, connection.sentFrames.count < 2 {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(!connection.closed)
        let replies = connection.sentFrames.compactMap { data -> ReplyEnvelope? in
            guard case .reply(let reply)? = try? JSONDecoder().decode(WireEnvelope.self, from: data) else { return nil }
            return reply
        }
        #expect(replies.count == 1)
        #expect(replies.first?.errorMessage != nil)
        withExtendedLifetime(greeter) {}
    }
}

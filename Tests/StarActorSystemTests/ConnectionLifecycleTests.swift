//
//  ConnectionLifecycleTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 26.07.26.
//

import Foundation
@testable import StarActorSystem
import Testing

struct ConnectionLifecycleTests {

    @Test("Remote call without a connection throws immediately")
    func notConnected() async throws {
        let client = StarActorSystem(name: "client")
        let proxy = try Greeter.resolve(id: .greeter, using: client)

        await #expect(throws: StarRemoteCallError.self) {
            _ = try await proxy.greet(name: "Julian")
        }
    }

    @Test("Remote call while attached but not up fails fast")
    func attachedButNotUpFailsFast() async throws {
        let client = StarActorSystem(name: "client", remoteCallTimeout: .seconds(60))
        await client.attach(InMemoryWireConnection(blackhole: true))
        let proxy = try Greeter.resolve(id: .greeter, using: client)

        let start = ContinuousClock.now
        await #expect(throws: StarRemoteCallError.self) {
            _ = try await proxy.greet(name: "Julian")
        }
        // Must fail immediately (pre-handshake), not run into the 60 s timeout.
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test("Remote call without a reply times out")
    func timeout() async throws {
        let client = StarActorSystem(name: "client", remoteCallTimeout: .milliseconds(200))
        try await client.attachUp(InMemoryWireConnection(blackhole: true))
        let proxy = try Greeter.resolve(id: .greeter, using: client)

        let start = ContinuousClock.now
        await #expect(throws: StarRemoteCallError.self) {
            _ = try await proxy.greet(name: "Julian")
        }
        #expect(ContinuousClock.now - start >= .milliseconds(200))
    }

    @Test("Detach mid-call fails the pending call immediately")
    func detachFailsPendingCalls() async throws {
        let client = StarActorSystem(name: "client", remoteCallTimeout: .seconds(60))
        let connection = InMemoryWireConnection(blackhole: true)
        try await client.attachUp(connection)
        let proxy = try Greeter.resolve(id: .greeter, using: client)

        let callTask = Task {
            try await proxy.greet(name: "Julian")
        }
        // Wait until the call frame is actually on the wire, then cut the link.
        try await connection.waitForCallFrame()
        await client.detach(connection)

        let start = ContinuousClock.now
        await #expect(throws: StarRemoteCallError.self) {
            _ = try await callTask.value
        }
        // Must fail via failAll, not by running into the 60 s timeout.
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test("Latest connection wins: second attach closes the first and fails its pending calls")
    func latestConnectionWins() async throws {
        let client = StarActorSystem(name: "client", remoteCallTimeout: .seconds(60))
        let first = InMemoryWireConnection(blackhole: true)
        try await client.attachUp(first)
        let proxy = try Greeter.resolve(id: .greeter, using: client)

        let callTask = Task {
            try await proxy.greet(name: "Julian")
        }
        try await first.waitForCallFrame()

        let second = InMemoryWireConnection(blackhole: true)
        await client.attach(second)

        #expect(first.closed)
        #expect(!second.closed)
        await #expect(throws: StarRemoteCallError.self) {
            _ = try await callTask.value
        }
    }

    @Test("Stale connection's detach does not kill the current connection")
    func staleDetachIsIgnored() async throws {
        let system = StarActorSystem(name: "server")
        let stale = InMemoryWireConnection(blackhole: true)
        await system.attach(stale)
        let current = InMemoryWireConnection(blackhole: true)
        try await system.attachUp(current)
        #expect(system.latestConnectionStatus == .up)

        // The replaced socket's onClose fires late — must be a no-op.
        await system.detach(stale)

        #expect(system.latestConnectionStatus == .up)
        #expect(system.isConnected)
    }

    @Test("Frames from a stale connection are ignored")
    func staleFramesAreIgnored() async throws {
        let system = StarActorSystem(name: "server")
        let stale = InMemoryWireConnection(blackhole: true)
        await system.attach(stale)
        let current = InMemoryWireConnection(blackhole: true)
        await system.attach(current)

        // A hello arriving on the stale connection must not mark the system up.
        let hello = try JSONEncoder().encode(WireEnvelope.hello(Hello(protocolVersion: StarActorSystem.protocolVersion)))
        await system.receive(hello, from: stale)
        #expect(system.latestConnectionStatus == .connecting)
        #expect(!system.isConnected)

        // The same hello on the current connection completes the handshake.
        await system.receive(hello, from: current)
        #expect(system.isConnected)
    }

    @Test("Hello protocol version mismatch closes the connection and never goes up")
    func helloVersionMismatch() async throws {
        let system = StarActorSystem(name: "server")
        let connection = InMemoryWireConnection(blackhole: true)
        await system.attach(connection)

        let mismatchedHello = try JSONEncoder().encode(WireEnvelope.hello(Hello(protocolVersion: 999)))
        await system.receive(mismatchedHello, from: connection)

        #expect(connection.closed)
        #expect(system.latestConnectionStatus != .up)
        #expect(!system.isConnected)
    }

    @Test("Server replies hello when it receives the client hello")
    func serverRepliesHello() async throws {
        let server = StarActorSystem(name: "server")
        let connection = InMemoryWireConnection(blackhole: true)
        await server.attach(connection)

        let clientHello = try JSONEncoder().encode(WireEnvelope.hello(Hello(protocolVersion: 1)))
        await server.receive(clientHello, from: connection)

        let frames = connection.sentFrames
        #expect(frames.count == 1)
        let reply = try JSONDecoder().decode(WireEnvelope.self, from: try #require(frames.first))
        guard case .hello(let hello) = reply else {
            Issue.record("expected hello reply, got \(reply)")
            return
        }
        #expect(hello.protocolVersion == 1)
        #expect(server.isConnected)
    }

    @Test("Reply arriving before wait is reached resolves the call (early-reply race)")
    func earlyReplyBeforeWait() async throws {
        let pendingCalls = PendingCalls()
        let id = UUID()
        let reply = ReplyEnvelope(callID: id, result: nil, errorMessage: nil)

        await pendingCalls.begin(id)
        // The reply lands before anyone waits — must be buffered, not dropped.
        await pendingCalls.settle(id, with: .success(reply))

        let received = try await pendingCalls.wait(for: id, timeout: .seconds(5))
        #expect(received.callID == id)
        #expect(received.errorMessage == nil)
    }
}

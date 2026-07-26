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

    @Test("Remote call without a reply times out")
    func timeout() async throws {
        let client = StarActorSystem(name: "client", remoteCallTimeout: .milliseconds(200))
        await client.attach(InMemoryWireConnection(blackhole: true))
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
        await client.attach(InMemoryWireConnection(blackhole: true))
        let proxy = try Greeter.resolve(id: .greeter, using: client)

        let callTask = Task {
            try await proxy.greet(name: "Julian")
        }
        // Give the call a moment to get in flight, then cut the link.
        try await Task.sleep(for: .milliseconds(100))
        await client.detach()

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
        await client.attach(first)
        let proxy = try Greeter.resolve(id: .greeter, using: client)

        let callTask = Task {
            try await proxy.greet(name: "Julian")
        }
        try await Task.sleep(for: .milliseconds(100))

        let second = InMemoryWireConnection(blackhole: true)
        await client.attach(second)

        #expect(first.closed)
        #expect(!second.closed)
        await #expect(throws: StarRemoteCallError.self) {
            _ = try await callTask.value
        }
    }

    @Test("Hello protocol version mismatch closes the connection and never goes up")
    func helloVersionMismatch() async throws {
        let system = StarActorSystem(name: "server")
        let connection = InMemoryWireConnection(blackhole: true)
        await system.attach(connection)

        let mismatchedHello = try JSONEncoder().encode(WireEnvelope.hello(Hello(protocolVersion: 999)))
        await system.receive(mismatchedHello)

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
        await server.receive(clientHello)

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
}

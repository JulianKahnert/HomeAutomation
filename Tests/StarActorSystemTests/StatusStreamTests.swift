//
//  StatusStreamTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 26.07.26.
//

import Foundation
@testable import StarActorSystem
import Testing

struct StatusStreamTests {

    private func helloFrame(version: Int = 1) throws -> Data {
        try JSONEncoder().encode(WireEnvelope.hello(Hello(protocolVersion: version)))
    }

    @Test("Stream is seeded with the current status")
    func seededValue() async throws {
        let system = StarActorSystem(name: "server")
        var iterator = system.makeConnectionStatusStream().makeAsyncIterator()

        #expect(await iterator.next() == .connecting)
    }

    @Test("Stream yields connecting → up → error → up transitions")
    func transitions() async throws {
        let system = StarActorSystem(name: "server")
        var iterator = system.makeConnectionStatusStream().makeAsyncIterator()
        #expect(await iterator.next() == .connecting)

        // Attach + hello handshake → .up
        await system.attach(InMemoryWireConnection(blackhole: true))
        await system.receive(try helloFrame())
        #expect(await iterator.next() == .up)

        // Socket closed after being up → .error
        await system.detach()
        #expect(await iterator.next() == .error)

        // New socket → .connecting, handshake → .up
        await system.attach(InMemoryWireConnection(blackhole: true))
        #expect(await iterator.next() == .connecting)
        await system.receive(try helloFrame())
        #expect(await iterator.next() == .up)
    }

    @Test("Detach before ever being up keeps status connecting")
    func detachBeforeUp() async throws {
        let system = StarActorSystem(name: "server")
        await system.attach(InMemoryWireConnection(blackhole: true))
        await system.detach()

        #expect(system.latestConnectionStatus == .connecting)
    }

    @Test("Multiple subscribers each receive updates")
    func multipleSubscribers() async throws {
        let system = StarActorSystem(name: "server")
        var first = system.makeConnectionStatusStream().makeAsyncIterator()
        var second = system.makeConnectionStatusStream().makeAsyncIterator()
        #expect(await first.next() == .connecting)
        #expect(await second.next() == .connecting)

        await system.attach(InMemoryWireConnection(blackhole: true))
        await system.receive(try helloFrame())

        #expect(await first.next() == .up)
        #expect(await second.next() == .up)
    }

    @Test("isReconnect truth table", arguments: [
        (ConnectionStatus.up, ConnectionStatus?.none, true),
        (.up, .connecting, true),
        (.up, .error, true),
        (.up, .up, false),
        (.connecting, .none, false),
        (.connecting, .up, false),
        (.connecting, .error, false),
        (.error, .none, false),
        (.error, .up, false),
        (.error, .connecting, false)
    ])
    func isReconnect(status: ConnectionStatus, previous: ConnectionStatus?, expected: Bool) {
        #expect(status.isReconnect(from: previous) == expected)
    }
}

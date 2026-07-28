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
        let first = InMemoryWireConnection(blackhole: true)
        await system.attach(first)
        await system.receive(try helloFrame(), from: first)
        #expect(await iterator.next() == .up)

        // Socket closed after being up → .error
        await system.detach(first)
        #expect(await iterator.next() == .error)

        // New socket → .connecting, handshake → .up
        let second = InMemoryWireConnection(blackhole: true)
        await system.attach(second)
        #expect(await iterator.next() == .connecting)
        await system.receive(try helloFrame(), from: second)
        #expect(await iterator.next() == .up)
    }

    @Test("Detach before ever being up keeps status connecting")
    func detachBeforeUp() async throws {
        let system = StarActorSystem(name: "server")
        let connection = InMemoryWireConnection(blackhole: true)
        await system.attach(connection)
        await system.detach(connection)

        #expect(system.latestConnectionStatus == .connecting)
    }

    @Test("Multiple subscribers each receive updates")
    func multipleSubscribers() async throws {
        let system = StarActorSystem(name: "server")
        var first = system.makeConnectionStatusStream().makeAsyncIterator()
        var second = system.makeConnectionStatusStream().makeAsyncIterator()
        #expect(await first.next() == .connecting)
        #expect(await second.next() == .connecting)

        let connection = InMemoryWireConnection(blackhole: true)
        await system.attach(connection)
        await system.receive(try helloFrame(), from: connection)

        #expect(await first.next() == .up)
        #expect(await second.next() == .up)
    }

    @Test("Handshake stream fires once per completed hello, including rapid replacement")
    func handshakeStreamBuffersRapidReplacements() async throws {
        let system = StarActorSystem(name: "server")
        let stream = system.makeHandshakeCompletedStream()

        // Two attach/hello cycles back-to-back BEFORE anyone consumes the
        // stream — the missed-resync scenario. Both events must be buffered.
        let first = InMemoryWireConnection(blackhole: true)
        await system.attach(first)
        await system.receive(try helloFrame(), from: first)

        let second = InMemoryWireConnection(blackhole: true)
        await system.attach(second)
        await system.receive(try helloFrame(), from: second)

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() != nil)
        #expect(await iterator.next() != nil)
    }

    @Test("Handshake stream is not seeded before the first handshake")
    func handshakeStreamNotSeeded() async throws {
        let system = StarActorSystem(name: "server")
        let stream = system.makeHandshakeCompletedStream()

        let received = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next() != nil
            }
            group.addTask {
                try? await Task.sleep(for: .milliseconds(100))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(!received)
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

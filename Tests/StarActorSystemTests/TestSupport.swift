//
//  TestSupport.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 26.07.26.
//

import Distributed
import Foundation
@testable import StarActorSystem

/// In-memory `WireConnection` delivering frames directly into the peer system.
/// Records all sent frames so tests can assert on the wire content.
final class InMemoryWireConnection: WireConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var _closed = false
    private var _sentFrames: [Data] = []
    private let deliver: @Sendable (Data) async -> Void
    /// When true, frames are recorded but never delivered (simulates a dead link).
    let blackhole: Bool

    init(blackhole: Bool = false, deliver: @escaping @Sendable (Data) async -> Void = { _ in }) {
        self.blackhole = blackhole
        self.deliver = deliver
    }

    var closed: Bool { lock.withLock { _closed } }
    var sentFrames: [Data] { lock.withLock { _sentFrames } }

    func send(_ data: Data) async throws {
        let closed = lock.withLock {
            if !_closed { _sentFrames.append(data) }
            return _closed
        }
        if closed { throw StarRemoteCallError(message: "connection closed") }
        guard !blackhole else { return }
        await deliver(data)
    }

    func close() async {
        lock.withLock { _closed = true }
    }

    /// Cross-wire two systems, attach both connections, and complete the hello
    /// handshake (system A acts as the "client" and sends the first hello).
    @discardableResult
    static func makePair(_ systemA: StarActorSystem, _ systemB: StarActorSystem) async -> (InMemoryWireConnection, InMemoryWireConnection) {
        let aToB = InMemoryWireConnection { [weak systemB] data in
            await systemB?.receive(data)
        }
        let bToA = InMemoryWireConnection { [weak systemA] data in
            await systemA?.receive(data)
        }
        await systemA.attach(aToB)
        await systemB.attach(bToA)
        await systemA.sendHello()
        return (aToB, bToA)
    }
}

// MARK: - Test actors

distributed actor Greeter {
    typealias ActorSystem = StarActorSystem

    distributed func greet(name: String) -> String {
        "Hello, \(name)!"
    }

    distributed func doNothing() {
        // Void round-trip fixture.
    }

    distributed func alwaysThrows() throws {
        throw GreeterError.expected
    }

    distributed func slowEcho(_ value: Int, delayMilliseconds: Int) async -> Int {
        try? await Task.sleep(for: .milliseconds(delayMilliseconds))
        return value
    }

    distributed func add(_ lhs: Int, _ rhs: Int) -> Int {
        lhs + rhs
    }
}

enum GreeterError: Error {
    case expected
}

extension StarActorID {
    static let greeter = StarActorID("greeter")
}

/// Builds a connected (client, server) system pair with a `Greeter` registered
/// on the server and a remote proxy resolved on the client.
func makeConnectedGreeterPair(
    remoteCallTimeout: Duration = .seconds(5)
) async throws -> (client: StarActorSystem, server: StarActorSystem, serverGreeter: Greeter, proxy: Greeter) {
    let client = StarActorSystem(name: "client", remoteCallTimeout: remoteCallTimeout)
    let server = StarActorSystem(name: "server", remoteCallTimeout: remoteCallTimeout)
    let greeter = server.makeActor(id: .greeter) { Greeter(actorSystem: server) }
    await InMemoryWireConnection.makePair(client, server)
    let proxy = try Greeter.resolve(id: .greeter, using: client)
    return (client, server, greeter, proxy)
}

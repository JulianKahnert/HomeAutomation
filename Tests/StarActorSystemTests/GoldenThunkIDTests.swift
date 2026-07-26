//
//  GoldenThunkIDTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 26.07.26.
//
//  Freezes the `RemoteCallTarget.identifier` (mangled thunk name) contract.
//  The module name is part of the mangled name and thus part of the wire
//  format — renaming a module, actor, or distributed method breaks deployed
//  peers. This suite covers the test-target actors.
//
//  PHASE 2 PLACEHOLDER: once the receiver actors in module `Adapter`
//  (`HomeEventReceiver`, `HomeKitCommandReceiver`) are wired to
//  StarActorSystem, add a golden test here asserting the thunk IDs of their
//  5 distributed methods against stored constants.
//

import Foundation
@testable import StarActorSystem
import Testing

struct GoldenThunkIDTests {

    /// Captures the wire `target` strings produced by calling each distributed
    /// method through the in-memory pair, then asserts them against frozen constants.
    @Test("Golden thunk IDs for test actors")
    func testActorThunkIDs() async throws {
        let client = StarActorSystem(name: "client", remoteCallTimeout: .seconds(5))
        let server = StarActorSystem(name: "server", remoteCallTimeout: .seconds(5))
        _ = server.makeActor(id: .greeter) { Greeter(actorSystem: server) }
        let (clientConnection, _) = await InMemoryWireConnection.makePair(client, server)
        let proxy = try Greeter.resolve(id: .greeter, using: client)

        _ = try await proxy.greet(name: "Julian")
        try await proxy.doNothing()
        try? await proxy.alwaysThrows()
        _ = try await proxy.slowEcho(1, delayMilliseconds: 0)
        _ = try await proxy.add(1, 2)

        let targets = try clientConnection.sentFrames.compactMap { frame -> String? in
            guard case .call(let call) = try JSONDecoder().decode(WireEnvelope.self, from: frame) else { return nil }
            return call.target
        }

        #expect(targets == [
            "$s20StarActorSystemTests7GreeterC5greet4nameS2S_tYaKFTE",
            "$s20StarActorSystemTests7GreeterC9doNothingyyYaKFTE",
            "$s20StarActorSystemTests7GreeterC12alwaysThrowsyyYaKFTE",
            "$s20StarActorSystemTests7GreeterC8slowEcho_17delayMillisecondsS2i_SitYaKFTE",
            "$s20StarActorSystemTests7GreeterC3addyS2i_SitYaKFTE"
        ])
    }
}

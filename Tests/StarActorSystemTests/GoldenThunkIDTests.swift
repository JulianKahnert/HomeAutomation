//
//  GoldenThunkIDTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 26.07.26.
//
//  Freezes the `RemoteCallTarget.identifier` (mangled thunk name) contract.
//  The module name is part of the mangled name and thus part of the wire
//  format — renaming a module, actor, or distributed method breaks deployed
//  peers. This suite covers the test-target actors and the production
//  receiver actors in module `Adapter`.
//

import Adapter
import Foundation
import HAModels
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

    /// Freezes the wire `target` strings of the 5 production receiver methods.
    ///
    /// FROZEN CONTRACT: the module name `Adapter` (and the actor/method names +
    /// parameter types, including argument types from module `HAModels`) are
    /// mangled into these identifiers. Renaming the module, the actors, the
    /// distributed methods, or their signatures changes the wire format and
    /// breaks already-deployed peers — if this test fails, that is the bug,
    /// not the constants.
    @Test("Golden thunk IDs for Adapter receiver actors")
    func receiverActorThunkIDs() async throws {
        let adapterSystem = StarActorSystem(name: "adapter", remoteCallTimeout: .seconds(5))
        let serverSystem = StarActorSystem(name: "server", remoteCallTimeout: .seconds(5))

        let (_, eventContinuation) = AsyncStream.makeStream(of: HomeEvent.self)
        _ = serverSystem.makeActor(id: .homeEventReceiver) {
            HomeEventReceiver(continuation: eventContinuation, actorSystem: serverSystem)
        }
        _ = adapterSystem.makeActor(id: .homeKitCommandReceiver) {
            HomeKitCommandReceiver(actorSystem: adapterSystem, adapter: FakeHomeKitAdapter())
        }

        let (adapterConnection, serverConnection) = await InMemoryWireConnection.makePair(adapterSystem, serverSystem)
        let eventProxy = try HomeEventReceiver.resolve(id: .homeEventReceiver, using: adapterSystem)
        let commandProxy = try HomeKitCommandReceiver.resolve(id: .homeKitCommandReceiver, using: serverSystem)

        let entityId = EntityId(placeId: "place", name: "name", characteristicsName: nil, characteristic: .switcher)

        // adapter → server
        try await eventProxy.process(event: .change(entity: EntityStorageItem(entityId: entityId)))
        // server → adapter
        _ = try await commandProxy.getAllEntitiesLive()
        try await commandProxy.findEntity(entityId)
        try await commandProxy.perform(.turnOn(entityId))
        try await commandProxy.trigger(scene: "some scene")

        let adapterTargets = try targets(sentOver: adapterConnection)
        let serverTargets = try targets(sentOver: serverConnection)

        #expect(adapterTargets == [
            "$s7Adapter17HomeEventReceiverC7process5eventy8HAModels0bC0O_tYaKFTE"
        ])
        #expect(serverTargets == [
            "$s7Adapter22HomeKitCommandReceiverC18getAllEntitiesLiveSay8HAModels17EntityStorageItemVGyYaKFTE",
            "$s7Adapter22HomeKitCommandReceiverC10findEntityyy8HAModels0G2IdVYaKFTE",
            "$s7Adapter22HomeKitCommandReceiverC7performyy8HAModels0B15ManagableActionOYaKFTE",
            "$s7Adapter22HomeKitCommandReceiverC7trigger5sceneySS_tYaKFTE"
        ])
    }

    /// Extracts the `target` of every `.call` frame sent over `connection`.
    private func targets(sentOver connection: InMemoryWireConnection) throws -> [String] {
        try connection.sentFrames.compactMap { frame -> String? in
            guard case .call(let call) = try JSONDecoder().decode(WireEnvelope.self, from: frame) else { return nil }
            return call.target
        }
    }
}

/// Minimal `HomeKitAdapterable` fake — the thunk test only needs the calls to
/// execute, not real HomeKit behavior.
private struct FakeHomeKitAdapter: HomeKitAdapterable {
    func getAllEntitiesLive() async -> [EntityStorageItem] { [] }
    func findEntity(_ entity: EntityId) async throws {}
    func perform(_ action: HomeManagableAction) async throws {}
    func trigger(scene sceneName: String) async throws {}
}

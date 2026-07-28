//
//  RoundTripTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 26.07.26.
//

import Foundation
@testable import StarActorSystem
import Testing

struct RoundTripTests {

    @Test("Value-returning remote call round-trips")
    func valueReturn() async throws {
        let (_, _, _, proxy) = try await makeConnectedGreeterPair()

        let greeting = try await proxy.greet(name: "Julian")
        #expect(greeting == "Hello, Julian!")
    }

    @Test("Void remote call round-trips")
    func voidReturn() async throws {
        let (_, _, _, proxy) = try await makeConnectedGreeterPair()

        try await proxy.doNothing()
    }

    @Test("Remote error propagates as StarRemoteCallError")
    func throwingCall() async throws {
        let (_, _, _, proxy) = try await makeConnectedGreeterPair()

        await #expect(throws: StarRemoteCallError.self) {
            try await proxy.alwaysThrows()
        }
    }

    @Test("Concurrent calls with out-of-order replies resolve correctly")
    func concurrentOutOfOrderReplies() async throws {
        let (_, _, _, proxy) = try await makeConnectedGreeterPair()

        // The slow call is started first but replies last.
        async let slow = proxy.slowEcho(1, delayMilliseconds: 300)
        async let fast = proxy.slowEcho(2, delayMilliseconds: 10)

        let (slowResult, fastResult) = try await (slow, fast)
        #expect(slowResult == 1)
        #expect(fastResult == 2)
    }

    @Test("Multiple arguments are encoded and decoded in order")
    func multipleArguments() async throws {
        let (_, _, _, proxy) = try await makeConnectedGreeterPair()

        let sum = try await proxy.add(19, 23)
        #expect(sum == 42)
    }

    @Test("Call for unknown recipient replies with an error")
    func unknownRecipient() async throws {
        let (client, _, _, _) = try await makeConnectedGreeterPair()

        let strangerProxy = try Greeter.resolve(id: StarActorID("nobody-home"), using: client)
        await #expect(throws: StarRemoteCallError.self) {
            _ = try await strangerProxy.greet(name: "Julian")
        }
    }
}

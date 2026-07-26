//
//  GoldenWireFormatTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 26.07.26.
//
//  Freezes the wire format. Wire evolution is ADDITIVE-ONLY: if one of these
//  tests fails, the change breaks compatibility with deployed peers.
//

import Foundation
@testable import StarActorSystem
import Testing

struct GoldenWireFormatTests {

    private func encodeSorted(_ envelope: WireEnvelope) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try #require(String(bytes: try encoder.encode(envelope), encoding: .utf8))
    }

    @Test("Golden hello envelope JSON")
    func goldenHello() throws {
        let json = try encodeSorted(.hello(Hello(protocolVersion: 1)))
        #expect(json == #"{"hello":{"_0":{"protocolVersion":1}}}"#)
    }

    @Test("Golden call envelope JSON")
    func goldenCall() throws {
        let callID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let envelope = RemoteCallEnvelope(
            callID: callID,
            recipient: .homeEventReceiver,
            target: "some$mangled$thunk",
            arguments: [Data(#""Julian""#.utf8)]
        )
        let json = try encodeSorted(.call(envelope))
        // Arguments are Data → base64: "Julian" (with JSON quotes) == Ikp1bGlhbiI=
        #expect(json == #"{"call":{"_0":{"arguments":["Ikp1bGlhbiI="],"callID":"00000000-0000-0000-0000-000000000001","recipient":{"id":"home-event-receiver"},"target":"some$mangled$thunk"}}}"#)
    }

    @Test("Golden reply envelope JSON (success)")
    func goldenReplySuccess() throws {
        let callID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let json = try encodeSorted(.reply(ReplyEnvelope(callID: callID, result: Data("42".utf8), errorMessage: nil)))
        #expect(json == #"{"reply":{"_0":{"callID":"00000000-0000-0000-0000-000000000002","result":"NDI="}}}"#)
    }

    @Test("Golden reply envelope JSON (error)")
    func goldenReplyError() throws {
        let callID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000003"))
        let json = try encodeSorted(.reply(ReplyEnvelope(callID: callID, result: nil, errorMessage: "boom")))
        #expect(json == #"{"reply":{"_0":{"callID":"00000000-0000-0000-0000-000000000003","errorMessage":"boom"}}}"#)
    }

    @Test("Fixture JSON decodes (frozen contract)")
    func decodeFixture() throws {
        let fixture = #"{"call":{"_0":{"arguments":["Ikp1bGlhbiI="],"callID":"00000000-0000-0000-0000-000000000001","recipient":{"id":"home-event-receiver"},"target":"some$mangled$thunk"}}}"#
        let envelope = try JSONDecoder().decode(WireEnvelope.self, from: Data(fixture.utf8))
        guard case .call(let call) = envelope else {
            Issue.record("expected call envelope")
            return
        }
        #expect(call.recipient == .homeEventReceiver)
        #expect(call.target == "some$mangled$thunk")
        #expect(call.arguments == [Data(#""Julian""#.utf8)])
    }

    @Test("Older-shape fixture with unknown extra fields still parses (additive-only guard)")
    func decodeWithUnknownFields() throws {
        // Simulates a NEWER peer that added fields — this (older) side must tolerate them.
        let fixture = #"{"reply":{"_0":{"callID":"00000000-0000-0000-0000-000000000002","result":"NDI=","someFutureField":true}}}"#
        let envelope = try JSONDecoder().decode(WireEnvelope.self, from: Data(fixture.utf8))
        guard case .reply(let reply) = envelope else {
            Issue.record("expected reply envelope")
            return
        }
        #expect(reply.result == Data("42".utf8))
        #expect(reply.errorMessage == nil)
    }
}

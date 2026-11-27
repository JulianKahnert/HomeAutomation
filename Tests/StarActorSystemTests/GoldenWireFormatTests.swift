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
import HAModels
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
        let json = try encodeSorted(.hello(Hello(protocolVersion: StarActorSystem.protocolVersion)))
        #expect(json == #"{"hello":{"_0":{"protocolVersion":3}}}"#)
    }

    @Test("The protocol version is 3 since the value kind and value wire shape")
    func protocolVersionIsThree() {
        #expect(StarActorSystem.protocolVersion == 3)
    }

    @Test("Golden entity state JSON carries value kind and value")
    func goldenEntityState() throws {
        let id = EntityId(placeId: "Bad OG", name: "Sensor", characteristicsName: nil, characteristic: .temperatureSensor)
        let date = Date(timeIntervalSinceReferenceDate: 1000)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let item = EntityStorageItem(entityId: id, timestamp: date, temperatureInC: .init(value: 21.5, unit: .celsius), origin: .homekit)
        let json = try #require(String(bytes: try encoder.encode(item), encoding: .utf8))
        #expect(json == #"{"entityId":{"characteristicType":"temperatureSensor","name":"Sensor","placeId":"Bad OG"},"kind":"temperatureSensor","origin":"homekit","timestamp":1000,"value":{"number":{"_0":21.5}}}"#)
        let text = EntityStorageItem(entityId: id, timestamp: date, color: RGB(red: 0.5, green: 0.25, blue: 1), origin: .homekit)
        #expect(String(bytes: try encoder.encode(text), encoding: .utf8)?.contains(#""value":{"text":{"_0":"0.5 0.25 1.0"}}"#) == true)
    }

    @Test("Every value kind survives the wire with the same value")
    func entityStateRoundTrip() throws {
        for type in CharacteristicsType.allCases {
            let id = EntityId(placeId: "p", name: "e", characteristicsName: nil, characteristic: type)
            let value: Value = switch type.valueKind.descriptor?.shape {
            case .bool: .bool(true)
            case .text: .text("0.1 0.25 0.9")
            case .textWithNumber: .text("running 1800000000.0")
            default: type == .heatingMode ? .number(1) : .number(3)
            }
            let item = try #require(EntityStorageItem(entityId: id, timestamp: Date(timeIntervalSinceReferenceDate: 5), kind: type.valueKind, value: value, origin: .homekit))
            let back = try JSONDecoder().decode(EntityStorageItem.self, from: try JSONEncoder().encode(item))
            #expect(back == item, "\(type)")
            #expect(back.genericValue?.value == value, "\(type)")
        }
    }

    @Test("An unknown value kind fails to decode")
    func unknownKindFails() {
        let json = #"{"entityId":{"characteristicType":"temperatureSensor","name":"S","placeId":"p"},"kind":"future","origin":"homekit","timestamp":1,"value":{"number":{"_0":1}}}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(EntityStorageItem.self, from: Data(json.utf8)) }
    }

    @Test("Golden thermostat and thermostat reply JSON")
    func goldenThermostat() throws {
        let thermostat = Thermostat(placeId: "Bad OG", name: "Eve Thermo", characteristicsName: "Heizung")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(String(bytes: try encoder.encode(thermostat), encoding: .utf8)
                == #"{"characteristicsName":"Heizung","name":"Eve Thermo","placeId":"Bad OG"}"#)
        let bare = try encoder.encode(Thermostat(placeId: "a", name: "b", characteristicsName: nil))
        #expect(String(bytes: bare, encoding: .utf8) == #"{"name":"b","placeId":"a"}"#)
        let decoded = try JSONDecoder().decode(Thermostat.self, from: Data(#"{"characteristicsName":"Heizung","name":"Eve Thermo","placeId":"Bad OG","future":1}"#.utf8))
        #expect(decoded == thermostat)
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

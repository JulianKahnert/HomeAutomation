//
//  HealthCheckPingTests.swift
//  HomeAutomationKit
//

import Foundation
@testable import HAImplementations
import HAModels
import Testing

struct HealthCheckPingTests {

    private let url = URL(string: "https://example.com/ping/00000000-0000-0000-0000-000000000000")!

    @Test("Healthy pings the URL itself")
    func healthyPingsSuccess() throws {
        let request = try #require(HealthCheck.pingRequest(for: url, health: .healthy))

        #expect(request.url == url)
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
    }

    @Test("Degraded posts the reason to <url>/fail")
    func degradedPingsFail() throws {
        let request = try #require(HealthCheck.pingRequest(for: url, health: .degraded(reason: "no HomeKit event for 11 min")))

        #expect(request.url?.absoluteString == "https://example.com/ping/00000000-0000-0000-0000-000000000000/fail")
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == Data("no HomeKit event for 11 min".utf8))
    }

    @Test("Unknown health sends no ping")
    func unknownSkipsPing() {
        #expect(HealthCheck.pingRequest(for: url, health: .unknown(reason: "adapter not connected yet")) == nil)
    }
}

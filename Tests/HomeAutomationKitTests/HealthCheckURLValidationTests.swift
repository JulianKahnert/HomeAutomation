//
//  HealthCheckURLValidationTests.swift
//  HomeAutomationKit
//

import Foundation
@testable import HAImplementations
import Testing

struct HealthCheckURLValidationTests {

    @Test("Public https URLs are accepted", arguments: [
        "https://hc-ping.com/ef0777d6-77d2-4153-aa3e-9cea2f471d0c",
        "https://example.org/",
        "https://8.8.8.8/ping",
        "https://[2001:db8::1]/ping",
        "https://sub.domain.example:8443/path?x=1"
    ])
    func acceptsPublicHTTPS(urlString: String) throws {
        let url = try #require(URL(string: urlString))
        #expect(throws: Never.self) { try HealthCheck.validate(url) }
    }

    @Test("Non-https schemes are rejected", arguments: [
        "http://hc-ping.com/x",
        "ftp://example.org/",
        "file:///etc/passwd",
        "gopher://example.org/"
    ])
    func rejectsOtherSchemes(urlString: String) throws {
        let url = try #require(URL(string: urlString))
        #expect(throws: HealthCheck.URLValidationError.self) { try HealthCheck.validate(url) }
    }

    @Test("Internal hosts are rejected", arguments: [
        "https://localhost/",
        "https://127.0.0.1/",
        "https://10.0.0.5/",
        "https://172.16.0.1/",
        "https://172.31.255.254/",
        "https://192.168.1.3:8080/",
        "https://169.254.169.254/latest/meta-data/",
        "https://100.64.0.1/",
        "https://0.0.0.0/",
        "https://db:3306/",
        "https://cloudflared:2000/metrics",
        "https://printer.local/",
        "https://service.internal/",
        "https://app.localhost/",
        "https://[::1]/",
        "https://[fd12:3456::1]/",
        "https://[fe80::1]/",
        "https://[::ffff:10.0.0.1]/"
    ])
    func rejectsInternalHosts(urlString: String) throws {
        let url = try #require(URL(string: urlString))
        #expect(throws: HealthCheck.URLValidationError.self) { try HealthCheck.validate(url) }
    }

    @Test("Boundary addresses next to private ranges are public")
    func boundaries() {
        #expect(HealthCheck.isPublicHost("172.15.255.255"))
        #expect(HealthCheck.isPublicHost("172.32.0.1"))
        #expect(HealthCheck.isPublicHost("100.63.255.255"))
        #expect(HealthCheck.isPublicHost("100.128.0.1"))
        #expect(HealthCheck.isPublicHost("192.169.0.1"))
        #expect(HealthCheck.isPublicHost("11.0.0.1"))
        #expect(!HealthCheck.isPublicHost("224.0.0.1"))
        #expect(!HealthCheck.isPublicHost("255.255.255.255"))
    }
}

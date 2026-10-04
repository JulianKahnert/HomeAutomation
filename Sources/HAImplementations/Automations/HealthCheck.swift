//
//  HealthCheck.swift
//
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HAModels

public struct HealthCheck: Automatable {
    public var isActive = true
    public let name: String
    public let url: URL
    public var triggerEntityIds = Set<EntityId>()
    public var recordsRuns: Bool { false }

    public init(_ name: String, url: URL) {
        self.name = name
        self.url = url
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        guard case HomeEvent.time(_) = event else {
            return false
        }

        return true
    }

    public func execute(using hm: HomeManagable) async throws {
        // The URL comes from the (authenticated) config upload. Without this check the server
        // would act as a request proxy into the container network (`http://db:3306/`,
        // `http://cloudflared:2000/metrics`, cloud metadata endpoints, ...).
        try Self.validate(url)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let (_, response) = try await URLSession.shared.data(for: request)
        // Only the status is logged: the response body of an attacker-chosen URL must never
        // end up in the logs.
        let statusCode = (response as? HTTPURLResponse)?.statusCode
        log.debug("Healthcheck response status: \(statusCode.map(String.init) ?? "unknown")")
    }

    // MARK: - URL validation

    public enum URLValidationError: Error, Equatable, CustomStringConvertible {
        case unsupportedScheme(String?)
        case missingHost
        case nonPublicHost(String)

        public var description: String {
            switch self {
            case .unsupportedScheme(let scheme):
                return "HealthCheck URL must use https (got \(scheme ?? "no scheme"))"
            case .missingHost:
                return "HealthCheck URL has no host"
            case .nonPublicHost(let host):
                return "HealthCheck URL host '\(host)' is not a public host"
            }
        }
    }

    /// Accepts only `https` URLs pointing at a public host name or address.
    ///
    /// Rejected: any other scheme, loopback/private/link-local/CGNAT IPv4 ranges, loopback,
    /// unique-local and link-local IPv6 addresses, `localhost`, `.local`/`.internal`/`.localhost`
    /// names and bare single-label names such as docker service names (`db`, `cloudflared`).
    public static func validate(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https" else {
            throw URLValidationError.unsupportedScheme(url.scheme)
        }
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            throw URLValidationError.missingHost
        }
        guard isPublicHost(host) else {
            throw URLValidationError.nonPublicHost(host)
        }
    }

    static func isPublicHost(_ rawHost: String) -> Bool {
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        guard !host.isEmpty else { return false }

        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".internal") {
            return false
        }
        if let octets = ipv4Octets(host) {
            return isPublicIPv4(octets)
        }
        if host.contains(":") {
            return isPublicIPv6(host)
        }
        // Single-label names resolve inside the container network (docker service names).
        return host.contains(".")
    }

    private static func ipv4Octets(_ host: String) -> [UInt8]? {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { UInt8($0) }
        return octets.count == 4 ? octets : nil
    }

    private static func isPublicIPv4(_ octet: [UInt8]) -> Bool {
        switch (octet[0], octet[1]) {
        case (0, _), (10, _), (127, _):
            return false // "this" network, private, loopback
        case (100, 64...127):
            return false // carrier-grade NAT
        case (169, 254):
            return false // link-local (cloud metadata lives here)
        case (172, 16...31):
            return false // private
        case (192, 168):
            return false // private
        case (224...255, _):
            return false // multicast / reserved / broadcast
        default:
            return true
        }
    }

    private static func isPublicIPv6(_ host: String) -> Bool {
        let address = host.split(separator: "%").first.map(String.init) ?? host // strip zone id
        if address == "::" || address == "::1" { return false }
        if address.hasPrefix("::ffff:") { return false } // IPv4-mapped - treat as internal
        if address.hasPrefix("fc") || address.hasPrefix("fd") { return false } // unique local fc00::/7
        if address.hasPrefix("fe8") || address.hasPrefix("fe9") || address.hasPrefix("fea") || address.hasPrefix("feb") {
            return false // link-local fe80::/10
        }
        return true
    }
}

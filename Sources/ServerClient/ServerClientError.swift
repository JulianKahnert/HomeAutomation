//
//  ServerClientError.swift
//  ServerClient
//

import Foundation

/// Why a write to the server did not come back as `200`.
public enum ServerClientError: Error, Equatable, LocalizedError, Sendable {
    /// The server did not get to the change in time (503). The change is queued and will still run.
    case busy
    /// The server answered with another status than the route documents.
    case unexpected(status: Int)

    /// The error for an undocumented status of a write route.
    init(undocumentedStatus status: Int) {
        self = status == 503 ? .busy : .unexpected(status: status)
    }

    public var errorDescription: String? {
        switch self {
        case .busy:
            "The server is busy. The change is queued and applies in a moment."
        case .unexpected(let status):
            "The server answered unexpectedly (status \(status))."
        }
    }
}

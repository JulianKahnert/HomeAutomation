//
//  CoreCommandError+Http.swift
//  HomeAutomationServer
//

import HAApplicationLayer
import HAModels
import HTTPTypes
import OpenAPIRuntime
import Vapor

/// How a command that did not run to its end answers: one place for the OpenAPI routes (through
/// `ErrorHandlingMiddleware`) and the Vapor route `POST /config` (through `AbortError`).
extension CoreCommandError: AbortError, HTTPResponseConvertible {
    public var status: HTTPResponseStatus {
        switch self {
        case .timedOut, .dropped: return .serviceUnavailable
        case .unknownEntities: return .unprocessableEntity
        case .stateUnreadable: return .internalServerError
        }
    }

    public var reason: String {
        switch self {
        case .timedOut: return "The server core did not answer in time; the command is still handled"
        case .dropped: return "The server core is not running; the command was not handled"
        case .unknownEntities(let missing): return "Validation failed - Could not find the following entities: \(missing)"
        case .stateUnreadable: return "The state that was just set cannot be read back"
        }
    }

    public var httpStatus: HTTPTypes.HTTPResponse.Status {
        .init(code: Int(status.code))
    }
}

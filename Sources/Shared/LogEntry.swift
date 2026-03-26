//
//  LogEntry.swift
//  Shared
//
//  Structured log entry written as JSONL by FileLogHandler
//

import Foundation

public struct LogEntry: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: String
    public let label: String
    public let message: String

    public init(id: UUID = UUID(), timestamp: Date, level: String, label: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.label = label
        self.message = message
    }
}

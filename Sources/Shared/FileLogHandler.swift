//
//  FileLogHandler.swift
//  Shared
//
// Source: git@github.com:crspybits/swift-log-file.git

import Foundation
import Logging

/// Writes structured ``LogEntry`` JSON lines to a ``LogStore``.
public struct FileLogHandler: LogHandler {
    private let store: LogStore
    private let label: String

    public var logLevel: Logger.Level = .info

    private var prettyMetadata: String?
    public var metadata = Logger.Metadata() {
        didSet {
            self.prettyMetadata = self.prettify(self.metadata)
        }
    }

    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get { metadata[metadataKey] }
        set { metadata[metadataKey] = newValue }
    }

    public init(label: String, store: LogStore = .shared) {
        self.label = label
        self.store = store
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .sortedKeys
        return e
    }()

    public func log(event: LogEvent) {
        let mergedMetadata = event.metadata.map {
            self.metadata.merging($0) { _, new in new }
        }
        let pretty = mergedMetadata.flatMap { prettify($0) } ?? prettyMetadata
        let fullMessage = pretty.map { "\($0) " } ?? ""
        let entry = LogEntry(
            timestamp: Date(),
            level: "\(event.level)",
            label: label,
            message: "\(fullMessage)\(event.message)"
        )
        guard let data = try? Self.encoder.encode(entry),
              var jsonLine = String(data: data, encoding: .utf8) else { return }
        jsonLine.append("\n")
        Task {
            await store.write(jsonLine)
        }
    }

    private func prettify(_ metadata: Logger.Metadata) -> String? {
        metadata.isEmpty ? nil : metadata.map { "\($0)=\($1)" }.joined(separator: " ")
    }
}

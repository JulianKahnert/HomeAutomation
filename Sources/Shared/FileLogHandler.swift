//
//  Logging.swift
//  FlowKit Adapter
//
//  Created by Julian Kahnert on 25.02.25.
//
// Source: git@github.com:crspybits/swift-log-file.git

import Foundation
import Logging

extension FileLogHandler {
    actor FileHandlerOutputStream {
        private let url: URL
        private var nextRotationDate = Date.distantPast
        private var fileHandle: FileHandle?
        private var hasReportedFailure = false

        init(basePath url: URL) {
            self.url = url
        }

        func write(_ string: String) {
            // Opened on the first write and reopened after a failure: before the first unlock the
            // app can be woken in the background while its container is still unreadable.
            if fileHandle == nil || Date() > nextRotationDate {
                do {
                    fileHandle = try Self.getNewFileHandle(basePath: url)
                    nextRotationDate = Calendar.current.nextDate(after: Date(),
                                                                 matching: DateComponents(hour: 0, minute: 0, second: 0),
                                                                 matchingPolicy: .nextTime) ?? .distantPast
                    hasReportedFailure = false
                } catch {
                    handleFailure(error)
                }
            }

            guard let fileHandle, let data = string.data(using: .utf8) else { return }
            do {
                try fileHandle.write(contentsOf: data)
            } catch {
                handleFailure(error)
            }
        }

        /// Drops the handle so the next write reopens the file. Only the first failure in a row is
        /// reported, because the report is a log entry itself and comes back through this stream.
        private func handleFailure(_ error: any Error) {
            fileHandle = nil
            guard !hasReportedFailure else { return }
            hasReportedFailure = true
            Logger(label: "FileLogHandler").error("Log file unavailable, skipping file logging until it can be opened",
                                                  metadata: ["path": "\(url.path)", "error": "\(error)"])
        }

        private static func getNewFileHandle(basePath: URL) throws -> FileHandle {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            let date = Date()
            // format date to "path/to/2024-10-29.txt"
            let url = basePath.appendingPathComponent(formatter.string(from: date)).appendingPathExtension("txt")

            try FileManager.default.createDirectory(at: basePath, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try Data().write(to: url, options: .withoutOverwriting)
            }

            let fileHandle = try FileHandle(forWritingTo: url)
            try fileHandle.seekToEnd()
            return fileHandle
        }
    }
}

/// `FileLogHandler` is a simple implementation of `LogHandler` for directing
/// `Logger` output to a local file. Appends log output to this file, even across constructor calls.
struct FileLogHandler: LogHandler {
    private let stream: FileHandlerOutputStream
    private var label: String

    var logLevel: Logger.Level = .info

    private var prettyMetadata: String?
    var metadata = Logger.Metadata() {
        didSet {
            self.prettyMetadata = self.prettify(self.metadata)
        }
    }

    subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            return self.metadata[metadataKey]
        }
        set {
            self.metadata[metadataKey] = newValue
        }
    }

    init(label: String, stream: FileHandlerOutputStream) {
        self.label = label
        self.stream = stream
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    func log(event: LogEvent) {
        let prettyMetadata = event.metadata?.isEmpty ?? true
        ? self.prettyMetadata
        : self.prettify(self.metadata.merging(event.metadata!, uniquingKeysWith: { _, new in new }))

        let fullMessage = prettyMetadata.map { "\($0) " } ?? ""
        let entry = LogEntry(
            timestamp: Date(),
            level: "\(event.level)",
            label: self.label,
            message: "\(fullMessage)\(event.message)"
        )

        guard let data = try? Self.encoder.encode(entry),
              var jsonLine = String(data: data, encoding: .utf8) else {
            return
        }
        jsonLine.append("\n")

        Task {
            await stream.write(jsonLine)
        }
    }

    private func prettify(_ metadata: Logger.Metadata) -> String? {
        return !metadata.isEmpty ? metadata.map { "\($0)=\($1)" }.joined(separator: " ") : nil
    }
}

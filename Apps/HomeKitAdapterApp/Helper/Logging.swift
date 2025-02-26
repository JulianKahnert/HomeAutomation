//
//  Logging.swift
//  HomeKitAdapterApp
//
//  Created by Julian Kahnert on 25.02.25.
//
// Source: git@github.com:crspybits/swift-log-file.git

import Foundation
import Logging

extension FileLogHandler {
    // Adapted from https://nshipster.com/textoutputstream/
    public struct FileHandlerOutputStream: TextOutputStream, Sendable {
        private let url: URL
        private var nextRotationDate: Date
        private var fileHandle: FileHandle

        public init(basePath url: URL) {
            self.url = url
            self.fileHandle = Self.getNewFileHandle(basePath: url)
            self.nextRotationDate = Calendar.current.nextDate(after: Date(),
                                                              matching: DateComponents(hour: 0, minute: 0, second: 0),
                                                              matchingPolicy: .nextTime)!
        }

        public mutating func write(_ string: String) {
            if Date() > nextRotationDate {
                self.fileHandle = Self.getNewFileHandle(basePath: url)
                self.nextRotationDate = Calendar.current.nextDate(after: Date(),
                                                                  matching: DateComponents(hour: 0, minute: 0, second: 0),
                                                                  matchingPolicy: .nextTime)!
            }

            if let data = string.data(using: .utf8) {
                fileHandle.write(data)
            }
        }

        private static func getNewFileHandle(basePath: URL) -> FileHandle {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = .current
            let date = Date()
            // format date to "path/to/2024-10-29.txt"
            let url = basePath.appendingPathComponent(formatter.string(from: date)).appendingPathExtension("txt")

            if !FileManager.default.fileExists(atPath: url.path) {
                guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil) else {
                    fatalError()
                }
            }

            let fileHandle = try! FileHandle(forWritingTo: url)
            fileHandle.seekToEndOfFile()
            return fileHandle
        }
    }
}

/// `FileLogHandler` is a simple implementation of `LogHandler` for directing
/// `Logger` output to a local file. Appends log output to this file, even across constructor calls.
public struct FileLogHandler: LogHandler {
    private let stream: FileHandlerOutputStream
    private var label: String

    public var logLevel: Logger.Level = .info

    private var prettyMetadata: String?
    public var metadata = Logger.Metadata() {
        didSet {
            self.prettyMetadata = self.prettify(self.metadata)
        }
    }

    public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
        get {
            return self.metadata[metadataKey]
        }
        set {
            self.metadata[metadataKey] = newValue
        }
    }

    public init(label: String, stream: FileHandlerOutputStream) {
        self.label = label
        self.stream = stream
    }

    public func log(level: Logger.Level,
                    message: Logger.Message,
                    metadata: Logger.Metadata?,
                    source: String,
                    file: String,
                    function: String,
                    line: UInt) {

        let prettyMetadata = metadata?.isEmpty ?? true
            ? self.prettyMetadata
            : self.prettify(self.metadata.merging(metadata!, uniquingKeysWith: { _, new in new }))

        var stream = self.stream
        stream.write("\(self.timestamp()) \(level) \(self.label) :\(prettyMetadata.map { " \($0)" } ?? "") \(message)\n")
    }

    private func prettify(_ metadata: Logger.Metadata) -> String? {
        return !metadata.isEmpty ? metadata.map { "\($0)=\($1)" }.joined(separator: " ") : nil
    }

    private func timestamp() -> String {
        var buffer = [Int8](repeating: 0, count: 255)
        var timestamp = time(nil)
        let localTime = localtime(&timestamp)
        strftime(&buffer, buffer.count, "%Y-%m-%dT%H:%M:%S%z", localTime)
        return buffer.withUnsafeBufferPointer {
            $0.withMemoryRebound(to: CChar.self) {
                String(cString: $0.baseAddress!)
            }
        }
    }
}

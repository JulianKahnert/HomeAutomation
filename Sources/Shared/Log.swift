//
//  Entity.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
import Logging
#if canImport(os)
import LoggingOSLog
#endif

public protocol Log {
    var log: Logger { get }
    static var log: Logger { get }
}

public extension Log {
    static var log: Logger {
        Logger(label: String(describing: Self.self))
    }
    var log: Logger {
        Self.log
    }
}

public func initLogging(withFileLogging: Bool, logLevel: Logger.Level) {
    // Resolve the log directory once (and prune old daily files) before bootstrapping, so the
    // cleanup runs a single time rather than per logger label.
    let logBasePath = withFileLogging ? logFileDirectory() : nil
    if let logBasePath {
        deleteLogFiles(olderThanDays: 7, in: logBasePath)
    }

    LoggingSystem.bootstrap { label in
        var handlers: [LogHandler] = []

        #if canImport(os)
        handlers.append(LoggingOSLog(label: label))
        #else
        handlers.append(StreamLogHandler.standardOutput(label: label))
        #endif

        if let logBasePath {
            let stream = FileLogHandler.FileHandlerOutputStream(basePath: logBasePath)
            handlers.append(FileLogHandler(label: label, stream: stream))
        }

        var mpxHandler = MultiplexLogHandler(handlers)
        mpxHandler.logLevel = logLevel
        return mpxHandler
    }
}

/// Directory the `FileLogHandler` writes its daily log files to — a `logs` subfolder so the log
/// files don't clutter the app's Documents directory.
private func logFileDirectory() -> URL {
    #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS) || os(visionOS)
    let base = URL.documentsDirectory
    #else
    // Linux fallback: use the temporary directory.
    let base = FileManager.default.temporaryDirectory
    #endif
    let dir = base.appendingPathComponent("logs")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Deletes daily log files (`*.txt`) older than `days` so they don't accumulate on disk
/// indefinitely (the recurring wedge can take days/weeks to reappear).
private func deleteLogFiles(olderThanDays days: Int, in directory: URL) {
    let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 60 * 60)
    guard let files = try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
    ) else { return }
    for file in files where file.pathExtension == "txt" {
        guard let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
              modified < cutoff else { continue }
        try? FileManager.default.removeItem(at: file)
    }
}

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
    LoggingSystem.bootstrap { label in
        var handlers: [LogHandler] = []

        #if canImport(os)
        handlers.append(LoggingOSLog(label: label))
        #else
        handlers.append(StreamLogHandler.standardOutput(label: label))
        #endif

        if withFileLogging {
            #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS) || os(visionOS)
            let logBasePath = URL.documentsDirectory
            #else
            // Linux fallback: use temporary directory for logs
            let logBasePath = FileManager.default.temporaryDirectory.appendingPathComponent("logs")
            try? FileManager.default.createDirectory(at: logBasePath, withIntermediateDirectories: true)
            #endif
            let stream = FileLogHandler.FileHandlerOutputStream(basePath: logBasePath)
            handlers.append(FileLogHandler(label: label, stream: stream))
        }

        var mpxHandler = MultiplexLogHandler(handlers)
        mpxHandler.logLevel = logLevel
        return MultiplexLogHandler(handlers)
    }
}

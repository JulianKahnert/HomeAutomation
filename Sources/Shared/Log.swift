//
//  Entity.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation
import Logging
import LoggingOSLog

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
        var handlers: [LogHandler] = [LoggingOSLog(label: label)]

        if withFileLogging {
            let stream = FileLogHandler.FileHandlerOutputStream(basePath: URL.documentsDirectory)
            handlers.append(FileLogHandler(label: label, stream: stream))
        }

        var mpxHandler = MultiplexLogHandler(handlers)
        mpxHandler.logLevel = logLevel
        return MultiplexLogHandler(handlers)
    }
}

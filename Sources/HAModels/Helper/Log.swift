//
//  Entity.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 01.07.24.
//

import Logging

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

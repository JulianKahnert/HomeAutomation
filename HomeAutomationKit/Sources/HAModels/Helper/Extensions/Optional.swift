//
//  Optional.swift
//  
//
//  Created by Julian Kahnert on 04.07.24.
//

import Logging

public extension Optional {
    func get(with log: Logger, file: StaticString = #file, function: StaticString = #function, line: UInt = #line) throws -> Wrapped {
        guard let self else {
            log.error("Failed to get value (\(debugDescription)) [\(function) \(file): \(line)]")
            throw OptionalError.notFound
        }
        return self
    }
}

public enum OptionalError: String, Error {
    case notFound
}

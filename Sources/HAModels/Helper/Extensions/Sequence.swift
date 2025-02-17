//
//  Sequence.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 07.08.24.
//

public extension Sequence {
    func asyncMap<T>(
        _ transform: (Element) async throws -> T
    ) async rethrows -> [T] {
        var values = [T]()

        for element in self {
            try await values.append(transform(element))
        }

        return values
    }
}

//
//  HomeEvent.swift
//
//
//  Created by Julian Kahnert on 01.07.24.
//

import Foundation

public enum HomeEvent: Codable, Sendable {
    case change(entity: EntityStorageItem)
    case time(date: Date)
    case sunrise
    case sunset
}

extension HomeEvent: CustomStringConvertible, Equatable {
    public var description: String {
        switch self {
        case .change(let entityId):
            return "change(\(entityId))"
        case .time(date: let date):
            // in the "time" we do not use seconds/milliseconds because we use this for Equatable check
            return "time(\(date.formatted(date: .numeric, time: .shortened)))"
        case .sunrise:
            return "sunrise"
        case .sunset:
            return "sunset"
        }
    }

    // time will only compared hour/minute
    public static func == (lhs: HomeEvent, rhs: HomeEvent) -> Bool {
        return lhs.description == rhs.description
    }
}

//
//  LogIntervall.swift
//  HomeKitAdapterApp
//
//  Created by Julian Kahnert on 05.02.25.
//

enum LogIntervall: CaseIterable {
        case off, fiveSeconds, oneMinute, fiveMinutes
        var duration: Duration? {
            switch self {
            case .off:
                return nil
            case .fiveSeconds:
                return .seconds(5)
            case .oneMinute:
                return .minutes(1)
            case .fiveMinutes:
                return .minutes(5)
            }
        }
        var text: String {
            switch self {
            case .off:
                return "Off"
            case .fiveSeconds:
                return "5 seconds"
            case .oneMinute:
                return "1 minute"
            case .fiveMinutes:
                return "5 minutes"
            }
        }
    }

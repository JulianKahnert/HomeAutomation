//
//  Duration.swift
//  
//
//  Created by Julian Kahnert on 08.07.24.
//

import Foundation

public extension Duration {
    var timeInterval: TimeInterval {
        return Double(components.seconds)
    }

    static func milliseconds(_ milliseconds: Int64) -> Duration {
        return .seconds(Double(milliseconds) / 1000.0)
    }
    static func minutes<T>(_ minutes: T) -> Duration where T: BinaryInteger {
        return .seconds(minutes * 60)
    }
    static func minutes(_ minutes: Double) -> Duration {
        return .seconds(minutes * 60.0)
    }
    static func hours<T>(_ hours: T) -> Duration where T: BinaryInteger {
        return .minutes(hours * 60)
    }
    static func hours(_ hours: Double) -> Duration {
        return .minutes(hours * 60.0)
    }
}

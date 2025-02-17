//
//  Date.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 03.08.24.
//
// swiftlint:disable force_unwrapping

import Foundation

public extension Date {
    func percentageOfDay() -> Double {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: self)
        let totalSeconds = Double(components.hour! * 3600 + components.minute! * 60 + components.second!)
        return totalSeconds / 86400
    }

    func tomorrow() -> Date {
        return Calendar.current.date(byAdding: DateComponents(day: 1), to: self)!
    }

    func fourDaysAgo() -> Date {
        return Calendar.current.date(byAdding: DateComponents(day: -4), to: self)!
    }
}

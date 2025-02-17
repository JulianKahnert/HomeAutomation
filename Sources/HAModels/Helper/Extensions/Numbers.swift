//
//  Numbers.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 07.08.24.
//

extension Double {
    func clamped(to limits: ClosedRange<Double>) -> Double {
        return min(max(self, limits.lowerBound), limits.upperBound)
    }
}

public extension Float {
    func scale(to range: ClosedRange<Float>) -> Float {
        return (range.upperBound - range.lowerBound) * self + range.lowerBound
    }
}

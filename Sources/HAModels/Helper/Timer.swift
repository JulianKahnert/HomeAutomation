//
//  Timer.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 18.02.25.
//

import Foundation

extension Timer: @retroactive @unchecked Sendable {}
public extension Timer {
    static func publish(every duration: Duration) -> any AsyncSequence<Date, Never> {
        AsyncStream<Date> { continuation in
            // Compute the next date where the seconds are 0 (i.e. the next minute boundary).
            guard let nextMinute = Calendar.current.nextDate(after: Date(),
                                                             matching: DateComponents(second: 0),
                                                             matchingPolicy: .nextTime) else {
                continuation.finish()
                return
            }
            
            // Create a timer that fires first at the next minute boundary and then every 60 seconds.
            let timer = Timer(fire: nextMinute, interval: duration.timeInterval, repeats: true) { _ in
                continuation.yield(Date())
            }
            // Add the timer to the run loop.
            RunLoop.main.add(timer, forMode: .default)
            
            // Invalidate the timer when the stream is terminated.
            continuation.onTermination = { _ in
                timer.invalidate()
            }
        }
    }
}

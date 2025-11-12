//
//  Timer.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 18.02.25.
//

import Foundation
import Logging

extension Timer: Log {}
public extension Timer {
    static func publish(every duration: Duration) -> any AsyncSequence<Date, Never> {
        let (stream, continuation) = AsyncStream<Date>.makeStream(of: Date.self, bufferingPolicy: .bufferingNewest(1))

        Task {
            // Compute the next date where the seconds are 0 (i.e. the next minute boundary).
            var nextEventDate = Calendar.current.nextDate(after: Date(),
                                                       matching: DateComponents(second: 0),
                                                       matchingPolicy: .nextTime)!
            while true {
                // wait until the nextEventDate
                try? await Task.sleep(for: .seconds(nextEventDate.timeIntervalSinceNow))

                // send the signal
                continuation.yield(nextEventDate)

                // calculate the next event by adding the duration to avoid a clock drift
                nextEventDate = nextEventDate.addingTimeInterval(duration.timeInterval)
            }
        }

        return stream
    }
}

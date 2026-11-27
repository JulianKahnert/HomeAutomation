//
//  ClockJob.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 16.02.25.
//

import Foundation
import HAModels
import Logging
import Shared

struct ClockJob: Job, Log {
    let location: Location
    let homeEventSink: HomeEventSink

    func run() async {
        log.debug("Starting ClockJob")
        for await date in Timer.publish(every: .minutes(1)) {
            // trigger stream event
            homeEventSink.yield(.time(date: date))

            // trigger sunset/sunrise event
            if Sun.sunriseElevation(for: date, latitude: location.latitude, longitude: location.longitude) == .horizon {
                homeEventSink.yield(.sunrise)
            } else if Sun.sunsetElevation(for: date, latitude: location.latitude, longitude: location.longitude) == .horizon {
                homeEventSink.yield(.sunset)
            }
        }
    }
}

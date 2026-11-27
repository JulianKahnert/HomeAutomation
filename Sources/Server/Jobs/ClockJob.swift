//
//  ClockJob.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 16.02.25.
//

import Foundation
import HAModels

/// The clock events (`time`, `sunrise`, `sunset`) on every full minute, from the scheduler's one minute grid.
struct ClockJob: ScheduledJob {
    let name = "ClockJob"
    let cadence: Duration = .minutes(1)
    let location: Location
    let homeEventSink: HomeEventSink

    func run(plannedAt date: Date) async throws {
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

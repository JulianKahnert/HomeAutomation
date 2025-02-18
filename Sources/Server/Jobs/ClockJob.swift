//
//  ClockJob.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 16.02.25.
//

import Foundation
import HAModels

struct ClockJob: Job {
    let location: Location
    let homeEventsContinuation: AsyncStream<HomeEvent>.Continuation

    func run() async {
        for await date in Timer.publish(every: .seconds(5)) {
            // trigger stream event
            homeEventsContinuation.yield(.time(date: date))

            // trigger sunset/sunrise event
            let sunSchedule = Sun.schedule(latitude: location.latitude, longitude: location.longitude, date: date)
            if let sunrise = sunSchedule?.sunrise,
               Calendar.current.isDate(sunrise.date, equalTo: date, toGranularity: .minute) {
                homeEventsContinuation.yield(.sunrise)
            } else if let sunset = sunSchedule?.sunset,
                      Calendar.current.isDate(sunset.date, equalTo: date, toGranularity: .minute) {
                homeEventsContinuation.yield(.sunset)
            }
        }
    }
}

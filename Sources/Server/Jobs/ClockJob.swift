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
        while true {

            // calculate waiting duration
            let currentDate = Date()
            let calendar = Calendar.current
            let nextMinuteDate = calendar.date(byAdding: .minute, value: 1, to: currentDate)!
            let nextMinuteDateWithoutSeconds = calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextMinuteDate))!
            let timeInterval = nextMinuteDateWithoutSeconds.timeIntervalSince(currentDate)

            // wait until next minute starts, e.g. 12:42:00
            try! await Task.sleep(for: .seconds(timeInterval))

            // trigger stream event
            let date = Date()
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

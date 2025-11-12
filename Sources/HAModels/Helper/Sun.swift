//  Sun.swift
//  Created by Marco Arment on 1/17/21
//
//  Solar-math functions are directly translated from the NOAA Solar Calculator:
//  https://www.esrl.noaa.gov/gmd/grad/solcalc/
//
//  This is free and unencumbered software released into the public domain.
//
//  Anyone is free to copy, modify, publish, use, compile, sell, or
//  distribute this software, either in source code form or as a compiled
//  binary, for any purpose, commercial or non-commercial, and by any
//  means.
//
//  In jurisdictions that recognize copyright laws, the author or authors
//  of this software dedicate any and all copyright interest in the
//  software to the public domain. We make this dedication for the benefit
//  of the public at large and to the detriment of our heirs and
//  successors. We intend this dedication to be an overt act of
//  relinquishment in perpetuity of all present and future rights to this
//  software under copyright law.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
//  IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
//  OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
//  ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//
//  For more information, please refer to <http://unlicense.org/>

// swiftlint:disable identifier_name

import Foundation

public struct SunPosition {
    public var date: Date
    public var azimuth: Double = 0.0
    public var elevation: Double = 0.0
}

public struct SunSchedule {
    public var position: SunPosition

    public var startOfDay: SunPosition
    public var endOfDay: SunPosition
    public var solarNoon: SunPosition
    public var solarMidnight: SunPosition

    // Optional: some days in some locations never have a sunrise and/or sunset
    public var sunrise: SunPosition?
    public var sunset: SunPosition?
}

public class Sun {
    public static func schedule(latitude: Double, longitude: Double, date: Date?) -> SunSchedule? {
        return schedule(latitude: latitude, longitude: longitude, date: date, calendar: nil, timeZone: nil)
    }

    public static func schedule(latitude: Double, longitude: Double, date: Date?, calendar: Calendar?, timeZone: TimeZone?) -> SunSchedule? {
        let date = date ?? Date()
        guard let JT = JulianTime(calendar: calendar ?? Calendar.current, date: date, timeZone: timeZone ?? TimeZone.current) else { return nil }

        let currentPosition = azimuthAndElevation(date: date, T: JT.T, positionInDay: JT.positionInDay, latitude: latitude, longitude: longitude, timezoneOffset: JT.timezoneOffset)

        let solarNoonDate = JT.startOfDay.addingTimeInterval(solNoon(JD: JT.julianDay, longitude: longitude, timezoneOffset: JT.timezoneOffset) * 60.0)
        let solarMidnightDate = JT.startOfDay.addingTimeInterval(solMidnight(JD: JT.julianDay, longitude: longitude, timezoneOffset: JT.timezoneOffset) * 60.0)
        guard let solarNoon = position(latitude: latitude, longitude: longitude, date: solarNoonDate, calendar: calendar, timeZone: timeZone),
              let solarMidnight = position(latitude: latitude, longitude: longitude, date: solarMidnightDate, calendar: calendar, timeZone: timeZone),
              let startOfDay = position(latitude: latitude, longitude: longitude, date: JT.startOfDay, calendar: calendar, timeZone: timeZone),
              let endOfDay = position(latitude: latitude, longitude: longitude, date: JT.endOfDay, calendar: calendar, timeZone: timeZone)
        else { return nil }

        var sunrise: SunPosition?
        if let riseMin = sunriseOrSet(rise: true, JD: JT.julianDay, latitude: latitude, longitude: longitude, timezoneOffset: JT.timezoneOffset) {
            sunrise = position(latitude: latitude, longitude: longitude, date: JT.startOfDay.addingTimeInterval(riseMin * 60.0), calendar: calendar, timeZone: timeZone)
        }

        var sunset: SunPosition?
        if let setMin = sunriseOrSet(rise: false, JD: JT.julianDay, latitude: latitude, longitude: longitude, timezoneOffset: JT.timezoneOffset) {
            sunset = position(latitude: latitude, longitude: longitude, date: JT.startOfDay.addingTimeInterval(setMin * 60.0), calendar: calendar, timeZone: timeZone)
        }

        return SunSchedule(position: currentPosition, startOfDay: startOfDay, endOfDay: endOfDay, solarNoon: solarNoon, solarMidnight: solarMidnight, sunrise: sunrise, sunset: sunset)
    }

    public static func position(latitude: Double, longitude: Double, date: Date?) -> SunPosition? {
        return position(latitude: latitude, longitude: longitude, date: date, calendar: nil, timeZone: nil)
    }

    public static func position(latitude: Double, longitude: Double, date: Date?, calendar: Calendar?, timeZone: TimeZone?) -> SunPosition? {
        let date = date ?? Date()
        guard let JT = JulianTime(calendar: calendar ?? Calendar.current, date: date, timeZone: timeZone ?? TimeZone.current) else { return nil }
        return azimuthAndElevation(date: date, T: JT.T, positionInDay: JT.positionInDay, latitude: latitude, longitude: longitude, timezoneOffset: JT.timezoneOffset)
    }

    private struct JulianTime {
        var julianDay: Double
        var T: Double
        var positionInDay: Double
        var startOfDay: Date
        var endOfDay: Date
        var timezoneOffset: Double

        init?(calendar: Calendar, date: Date, timeZone: TimeZone) {
            var midnightBoundary = DateComponents()
            midnightBoundary.hour = 0
            let dateComponents = calendar.dateComponents([ .year, .month, .day ], from: date)
            guard let year = dateComponents.year, let month = dateComponents.month, let day = dateComponents.day,
                  let dayEnd = calendar.nextDate(after: date, matching: midnightBoundary, matchingPolicy: .nextTime)
            else { return nil }
            self.endOfDay = dayEnd

            self.startOfDay = calendar.startOfDay(for: date)
            let dayLength = endOfDay.timeIntervalSince(startOfDay)
            self.positionInDay = date.timeIntervalSince(startOfDay) / dayLength
            self.timezoneOffset = Double(timeZone.secondsFromGMT(for: date))

            self.julianDay = Sun.julianDay(year: year, month: month, day: day)
            let total = julianDay + positionInDay + (timezoneOffset / dayLength)
            self.T = Sun.julianCent(julianDay: total)
        }
    }

    private static func degreesToRadians(_ degrees: Double) -> Double { return degrees * .pi / 180 }
    private static func radiansToDegrees(_ radians: Double) -> Double { return radians * 180 / .pi }

    // MARK: NOAA Solar Calculator
    // All functions below are directly translated from https://www.esrl.noaa.gov/gmd/grad/solcalc/
    // Original JavaScript: https://www.esrl.noaa.gov/gmd/grad/solcalc/main.js

    private static func azimuthAndElevation(date: Date, T: Double, positionInDay: Double, latitude: Double, longitude: Double, timezoneOffset: Double) -> SunPosition {
        let localtime = positionInDay * 24.0 * 60.0
        let eqTime = equationOfTime(T: T) // slight diff
        let theta = sunDeclination(T: T)

        let solarTimeFix = eqTime + 4.0 * longitude - 60.0 * timezoneOffset / 3600.0
        var trueSolarTime = localtime + solarTimeFix
        while trueSolarTime > 1440.0 { trueSolarTime -= 1440.0 }

        var hourAngle = trueSolarTime / 4.0 - 180.0
        if hourAngle < -180.0 { hourAngle += 360.0 }

        let haRad = degreesToRadians(hourAngle)
        let latitudeRad = degreesToRadians(latitude)
        let thetaRad = degreesToRadians(theta)
        var csz = sin(latitudeRad) * sin(thetaRad) + cos(latitudeRad) * cos(thetaRad) * cos(haRad)
        if csz > 1.0 { csz = 1.0 } else if csz < -1.0 { csz = -1.0 }

        let zenith = radiansToDegrees(acos(csz))
        let azDenom = cos(latitudeRad) * sin(degreesToRadians(zenith))

        var azimuth = 0.0
        if abs(azDenom) > 0.001 {
            var azRad = (( sin(degreesToRadians(latitude)) * cos(degreesToRadians(zenith)) ) - sin(degreesToRadians(theta))) / azDenom
            if abs(azRad) > 1.0 {
                if azRad < 0 {
                    azRad = -1.0
                } else {
                    azRad = 1.0
                }
            }
            azimuth = 180.0 - radiansToDegrees(acos(azRad))
            if hourAngle > 0.0 { azimuth = -azimuth }
        } else {
            if latitude > 0.0 { azimuth = 180.0 }
        }
        if azimuth < 0.0 { azimuth += 360.0 }
        let exoatmElevation = 90.0 - zenith

        let refractionCorrection = refraction(elevation: exoatmElevation)
        let solarZen = zenith - refractionCorrection
        let elevation = 90.0 - solarZen

        return SunPosition(date: date, azimuth: azimuth, elevation: elevation)
    }

    private static func hourAngleSunrise(latitude: Double, declination: Double) -> Double {
        let latRad = degreesToRadians(latitude)
        let sdRad = degreesToRadians(declination)
        return acos(cos(degreesToRadians(90.833)) / (cos(latRad) * cos(sdRad)) - tan(latRad) * tan(sdRad))
    }

    private static func sunriseOrSetUTC(rise: Bool, JD: Double, latitude: Double, longitude: Double) -> Double {
        let t = julianCent(julianDay: JD)
        let eqTime = equationOfTime(T: t)
        let solarDec = sunDeclination(T: t)
        var hourAngle = hourAngleSunrise(latitude: latitude, declination: solarDec)
        if !rise { hourAngle = -hourAngle }
        let delta = longitude + radiansToDegrees(hourAngle)
        return 720 - (4.0 * delta) - eqTime // in minutes
    }

    private static func sunriseOrSet(rise: Bool, JD: Double, latitude: Double, longitude: Double, timezoneOffset: Double) -> Double? {
        let timeUTC = sunriseOrSetUTC(rise: rise, JD: JD, latitude: latitude, longitude: longitude)
        let newTimeUTC = sunriseOrSetUTC(rise: rise, JD: JD + timeUTC / 1440.0, latitude: latitude, longitude: longitude)
        if newTimeUTC.isNaN { return nil } // no sunrise/set on this day in this location (like North/South Pole)

        let timezone = timezoneOffset / 3600.0
        var timeLocal = newTimeUTC + (timezone * 60.0)
        if (timeLocal < 0.0) || (timeLocal >= 1440.0) {
            let increment = ((timeLocal < 0.0) ? 1.0 : -1.0)
            while (timeLocal < 0.0) || (timeLocal >= 1440.0) { timeLocal += increment * 1440.0 }
        }
        return timeLocal
    }

    private static func meanObliquityOfEcliptic(T: Double) -> Double { return 23.0 + (26.0 + ((21.448 - T * (46.8150 + T * (0.00059 - T * (0.001813)))) / 60.0)) / 60.0 }
    private static func obliquityCorrection(T: Double) -> Double { return meanObliquityOfEcliptic(T: T) + 0.00256 * cos(degreesToRadians(125.04 - 1934.136 * T)) }
    private static func eccentricityEarthOrbit(T: Double) -> Double { return 0.016708634 - T * (0.000042037 + 0.0000001267 * T) }
    private static func geometricMeanAnomalySun(T: Double) -> Double { return 357.52911 + T * (35999.05029 - 0.0001537 * T) }
    private static func sunTrueLong(T: Double) -> Double { return geometricMeanLongSun(T: T) + sunEqOfCenter(T: T) }
    private static func sunApparentLong(T: Double) -> Double { return sunTrueLong(T: T) - 0.00569 - 0.00478 * sin(degreesToRadians(125.04 - 1934.136 * T)) }

    private static func geometricMeanLongSun(T: Double) -> Double {
        var L0 = 280.46646 + T * (36000.76983 + T * (0.0003032))
        while L0 > 360.0 { L0 -= 360.0 }
        while L0 < 0.0 { L0 += 360.0 }
        return L0
    }

    private static func sunEqOfCenter(T: Double) -> Double {
        let mrad = degreesToRadians(geometricMeanAnomalySun(T: T))
        return sin(mrad) * (1.914602 - T * (0.004817 + 0.000014 * T)) + sin(mrad + mrad) * (0.019993 - 0.000101 * T) + sin(mrad + mrad + mrad) * 0.000289
    }

    private static func equationOfTime(T: Double) -> Double {
        let epsilon = obliquityCorrection(T: T)
        let l0 = geometricMeanLongSun(T: T)
        let e = eccentricityEarthOrbit(T: T)
        let m = geometricMeanAnomalySun(T: T)

        var y = tan(degreesToRadians(epsilon) / 2.0)
        y *= y

        let sin2l0 = sin(2.0 * degreesToRadians(l0))
        let sinm   = sin(degreesToRadians(m))
        let cos2l0 = cos(2.0 * degreesToRadians(l0))
        let sin4l0 = sin(4.0 * degreesToRadians(l0))
        let sin2m  = sin(2.0 * degreesToRadians(m))

        let Etime = y * sin2l0 - 2.0 * e * sinm + 4.0 * e * y * sinm * cos2l0 - 0.5 * y * y * sin4l0 - 1.25 * e * e * sin2m
        return radiansToDegrees(Etime) * 4.0 // in minutes of time
    }

    private static func sunDeclination(T: Double) -> Double {
        let e = obliquityCorrection(T: T)
        let lambda = sunApparentLong(T: T)
        let sint = sin(degreesToRadians(e)) * sin(degreesToRadians(lambda))
        return radiansToDegrees(asin(sint))
    }

    private static func refraction(elevation: Double) -> Double {
        var correction = 0.0

        if elevation > 85.0 { return 0.0 }

        let te = tan(degreesToRadians(elevation))
        let te3 = te * te * te
        if elevation > 5.0 {
            correction = 58.1 / te - 0.07 / te3 + 0.000086 / (te3 * te * te)
        } else if elevation > -0.575 {
            correction = 1735.0 + elevation * (-518.2 + elevation * (103.4 + elevation * (-12.79 + elevation * 0.711) ) )
        } else {
            correction = -20.774 / te
        }
        return correction / 3600.0
    }

    private static func solNoon(JD: Double, longitude: Double, timezoneOffset: Double) -> Double {
        let timezone = timezoneOffset / 3600.0
        let tnoon = julianCent(julianDay: JD - longitude / 360.0)
        var eqTime = equationOfTime(T: tnoon)
        let solNoonOffset = 720.0 - (longitude * 4) - eqTime
        let newt = julianCent(julianDay: JD + solNoonOffset / 1440.0)
        eqTime = equationOfTime(T: newt)
        var solNoonLocal = 720 - (longitude * 4) - eqTime + (timezone * 60.0)// in minutes
        while solNoonLocal < 0.0 { solNoonLocal += 1440.0 }
        while solNoonLocal >= 1440.0 { solNoonLocal -= 1440.0 }
        return solNoonLocal
    }

    private static func solMidnight(JD: Double, longitude: Double, timezoneOffset: Double) -> Double {
        let timezone = timezoneOffset / 3600.0
        let tnoon = julianCent(julianDay: JD - longitude / 360.0)
        var eqTime = equationOfTime(T: tnoon)
        let solNoonOffset = 0.0 - (longitude * 4) - eqTime
        let newt = julianCent(julianDay: JD + solNoonOffset / 1440.0)
        eqTime = equationOfTime(T: newt)
        var solNoonLocal = 0.0 - (longitude * 4) - eqTime + (timezone * 60.0)// in minutes
        while solNoonLocal < 0.0 { solNoonLocal += 1440.0 }
        while solNoonLocal >= 1440.0 { solNoonLocal -= 1440.0 }
        return solNoonLocal
    }

    private static func julianDay(calendar: Calendar, date: Date) -> Double? {
        let dateComponents = calendar.dateComponents([ .year, .month, .day ], from: date)
        guard let year = dateComponents.year, let month = dateComponents.month, let day = dateComponents.day else { return nil }
        return julianDay(year: year, month: month, day: day)
    }

    private static func julianDay(year: Int, month: Int, day: Int) -> Double {
        var y = Double(year)
        var m = Double(month)
        let d = Double(day)

        if m <= 2.0 {
            y -= 1.0
            m += 12.0
        }

        let A = floor(y / 100.0)
        let B = 2 - A + floor(A / 4.0)
        y += 4716.0
        m += 1
        return floor(365.25 * y) + floor(30.6001 * m) + (d + B - 1524.5)
    }

    private static func julianCent(julianDay: Double) -> Double {
        return (julianDay - 2451545.0) / 36525.0
    }
}

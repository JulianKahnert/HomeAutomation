//
//  TibberService.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 09.09.24.
//

import Foundation
import HAModels
import Logging
import Shared
import TibberSwift

public actor TibberService: Log {
    public struct TodayPrice: Sendable {
        public let time: ClosedRange<Date>
        public let price: Double
    }

    private static let tibberApi = "https://api.tibber.com/v1-beta/gql"

    private let tibber: TibberSwift
    private var priceCache: (Date, [TodayPrice])?

    public init?() {
        guard let apiKey = ProcessInfo.processInfo.environment["TIBBER_API_KEY"] else {
            Self.log.critical("Failed to get Tibber API key from environment 'TIBBER_API_KEY'")
            return nil
        }
        self.tibber = TibberSwift(apiKey: apiKey)
    }

    public func getPricesToday() async throws -> [TodayPrice] {
        let date = Date()

        if let priceCache,
            Calendar.current.isDate(priceCache.0, inSameDayAs: date) {
            log.debug("Using cached Tibber prices from \(priceCache.0)")
            return priceCache.1
        }

        log.info("Fetching Tibber prices (cache miss or expired)")
        let start = ContinuousClock.now
        let response: PriceInfoToday
        do {
            response = try await tibber.priceInfoToday()
        } catch {
            let duration = start.duration(to: .now)
            log.error("Tibber API call failed after \(duration): \(error)")
            throw error
        }
        let duration = start.duration(to: .now)
        log.info("Tibber API responded in \(duration) with \(response.homes.count) home(s)")

        guard let home = response.homes.first else {
            log.error("Failed to get home - Tibber API returned empty homes array")
            return []
        }

        let sortedPrices = home.currentSubscription.priceInfo.today.sorted { $0.startsAt < $1.startsAt }
        let prices = sortedPrices.enumerated().map { index, price in
            let start = price.startsAt
            let end: Date
            if index + 1 < sortedPrices.count {
                end = sortedPrices[index + 1].startsAt
            } else {
                end = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: start)!

            }
            return TodayPrice(time: start...end, price: price.total)
        }

        log.info("Fetched \(prices.count) price entries for today")
        priceCache = (date, prices)
        return prices
    }

    public func getCheapestPricesToday(for duration: Duration) async throws -> [TodayPrice] {
        let prices = try await getPricesToday()
        guard !prices.isEmpty else { return [] }

        let sortedPrices = prices.sorted { $0.price < $1.price }

        var cheapPrices: [TodayPrice] = []
        var totalDuration: TimeInterval = 0
        for price in sortedPrices {
            cheapPrices.append(price)
            totalDuration += price.time.upperBound.timeIntervalSince(price.time.lowerBound)
            if totalDuration >= duration.timeInterval {
                break
            }
        }

        return cheapPrices
    }

    public func sendNotification(title: String, message: String) async {
        log.info("Sending Tibber notification: \(title)")
        let start = ContinuousClock.now
        do {
            _ = try await tibber.sendPushNotification(title: title, message: message)
            let duration = start.duration(to: .now)
            log.info("Tibber notification sent in \(duration)")
        } catch {
            let duration = start.duration(to: .now)
            log.error("Failed to send Tibber notification after \(duration): \(error)")
        }
    }
}

extension PriceInfoToday: @unchecked @retroactive Sendable {}
extension PushNotificationResult: @unchecked @retroactive Sendable {}
extension TibberSwift: @unchecked @retroactive Sendable {}

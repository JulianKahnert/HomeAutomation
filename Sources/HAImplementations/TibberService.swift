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
            return priceCache.1
        }

        let response = try await tibber.priceInfoToday()
        guard let home = response.homes.first else {
            log.critical("Failed to get home")
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
        log.info("Sending notification \(title) \(message)")
        do {
            _ = try await tibber.sendPushNotification(title: title, message: message)
        } catch {
            log.critical("Failed to send notification \(error.localizedDescription)")
        }
    }
}

extension PriceInfoToday: @unchecked @retroactive Sendable {}
extension PushNotificationResult: @unchecked @retroactive Sendable {}
extension TibberSwift: @unchecked @retroactive Sendable {}

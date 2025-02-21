//
//  TibberService.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 09.09.24.
//

 import Foundation
 import HAModels
 import Logging
 import TibberSwift

public actor TibberService: Log {
    public struct TodayPrice: Sendable {
        public let startsAt: Date
        public let total: Double
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

    public func getPricesToday() async -> [TodayPrice]? {
        let date = Date()

        if let priceCache,
           Calendar.current.isDate(priceCache.0, inSameDayAs: date) {
            return priceCache.1
        }

        do {
            let response = try await tibber.priceInfoToday()
            guard let home = response.homes.first else { return nil }
            let prices = home.currentSubscription.priceInfo.today
                .map { price in
                    TodayPrice(startsAt: price.startsAt, total: price.total)
                }
            priceCache = (date, prices)
            return prices
        } catch {
            log.critical("Failed to get today prices \(error.localizedDescription)")
            return nil
        }
    }

    public func getPriceIfCurrentlyLowestPriceHour() async -> Double? {
        let priceInfos = await getPricesToday()
        guard let priceInfos,
            priceInfos.count >= 2 else { return nil }

        let sortedPriceInfos = Array(priceInfos.sorted(by: { $0.total < $1.total }))
        let lowestPriceInfo = sortedPriceInfos[0]

        let hour = Calendar.current.component(.hour, from: Date())
        let isLowestPriceHour = hour == Calendar.current.component(.hour, from: lowestPriceInfo.startsAt)
        return isLowestPriceHour ? lowestPriceInfo.total : nil
    }

    public func getPriceIfCurrentlySecondLowestPriceHour() async -> Double? {
        let priceInfos = await getPricesToday()
        guard let priceInfos,
            priceInfos.count >= 2 else { return nil }

        let sortedPriceInfos = Array(priceInfos.sorted(by: { $0.total < $1.total }))
        let secondLowestPriceInfo = sortedPriceInfos[1]

        let hour = Calendar.current.component(.hour, from: Date())
        let isSecondLowestPriceHour = hour == Calendar.current.component(.hour, from: secondLowestPriceInfo.startsAt)

        return isSecondLowestPriceHour ? secondLowestPriceInfo.total : nil
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

 extension PriceInfoToday: @unchecked @retroactive Sendable { }
 extension PushNotificationResult: @unchecked @retroactive Sendable { }
 extension TibberSwift: @unchecked @retroactive Sendable { }

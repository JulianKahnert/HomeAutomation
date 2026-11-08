//
//  NotificationResubscriptionTests.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 08.11.26.
//

import Foundation
@testable import Shared
import Testing

struct NotificationResubscriptionTests {
    @Test("A normal refresh only sends a request when the flag differs", arguments: [
        (shouldSubscribe: true, isEnabled: false, expected: [true]),
        (shouldSubscribe: false, isEnabled: true, expected: [false]),
        (shouldSubscribe: true, isEnabled: true, expected: []),
        (shouldSubscribe: false, isEnabled: false, expected: [])
    ])
    func normalRefresh(shouldSubscribe: Bool, isEnabled: Bool, expected: [Bool]) {
        let requests = NotificationResubscription.notificationRequests(shouldSubscribe: shouldSubscribe, isNotificationEnabled: isEnabled, force: false)
        #expect(requests == expected)
    }

    @Test("A forced resubscribe re-registers characteristics the client believes enabled")
    func forcedResubscribeIgnoresStaleFlag() {
        // homed dropped the registration, the client-side flag still says enabled
        let requests = NotificationResubscription.notificationRequests(shouldSubscribe: true, isNotificationEnabled: true, force: true)
        #expect(requests == [false, true])
    }

    @Test("A forced resubscribe behaves like a normal refresh for everything else", arguments: [
        (shouldSubscribe: true, isEnabled: false, expected: [true]),
        (shouldSubscribe: false, isEnabled: true, expected: [false]),
        (shouldSubscribe: false, isEnabled: false, expected: [])
    ])
    func forcedResubscribeOtherwise(shouldSubscribe: Bool, isEnabled: Bool, expected: [Bool]) {
        let requests = NotificationResubscription.notificationRequests(shouldSubscribe: shouldSubscribe, isNotificationEnabled: isEnabled, force: true)
        #expect(requests == expected)
    }

    @Test("Only HMErrorDomain Code=80 counts as background access denied")
    func backgroundAccessDenied() {
        #expect(NotificationResubscription.isBackgroundAccessDenied(NSError(domain: "HMErrorDomain", code: 80)))
        #expect(!NotificationResubscription.isBackgroundAccessDenied(NSError(domain: "HMErrorDomain", code: 74)))
        #expect(!NotificationResubscription.isBackgroundAccessDenied(NSError(domain: "HMErrorDomain", code: 801)))
        #expect(!NotificationResubscription.isBackgroundAccessDenied(NSError(domain: NSURLErrorDomain, code: 80)))
    }
}

struct ResubscribeRequestsTests {
    @Test("Nothing requested, nothing to take")
    func empty() async {
        let requests = ResubscribeRequests()
        #expect(await requests.take() == nil)
    }

    @Test("A burst of requests is taken once, with each reason once")
    func burstCoalesces() async {
        let requests = ResubscribeRequests()
        await requests.request(reason: "homeManagerDidUpdateHomes")
        await requests.request(reason: "manualRefresh")
        await requests.request(reason: "homeManagerDidUpdateHomes")

        #expect(await requests.take() == ["homeManagerDidUpdateHomes", "manualRefresh"])
        #expect(await requests.take() == nil)
    }

    @Test("A throttled reason is accepted again only after the interval, even once taken")
    func throttledReason() async {
        let requests = ResubscribeRequests()
        let start = ContinuousClock.now

        #expect(await requests.request(reason: "backgroundAccessDenied", notWithin: .seconds(60), now: start))
        #expect(await requests.take() == ["backgroundAccessDenied"])

        #expect(await !requests.request(reason: "backgroundAccessDenied", notWithin: .seconds(60), now: start + .seconds(59)))
        #expect(await requests.take() == nil)

        #expect(await requests.request(reason: "backgroundAccessDenied", notWithin: .seconds(60), now: start + .seconds(60)))
        #expect(await requests.take() == ["backgroundAccessDenied"])
    }

    @Test("Throttling one reason leaves the others alone")
    func throttleIsPerReason() async {
        let requests = ResubscribeRequests()
        let start = ContinuousClock.now
        #expect(await requests.request(reason: "backgroundAccessDenied", notWithin: .seconds(60), now: start))

        await requests.request(reason: "manualRefresh")

        #expect(await requests.take() == ["backgroundAccessDenied", "manualRefresh"])
    }
}

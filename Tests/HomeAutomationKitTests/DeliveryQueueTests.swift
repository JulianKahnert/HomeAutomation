//
//  DeliveryQueueTests.swift
//  HomeAutomationKitTests
//

import Foundation
@testable import HAApplicationLayer
import HAModels
import Testing

@Suite("Delivery order")
struct DeliveryQueueTests {
    @Test("deliveries leave in the order of hand-over, also when the first send is slow")
    func orderHoldsWithSlowSend() async {
        let sender = GatedSender()
        let queue = DeliveryQueue(sender: sender)

        let first = Task { await queue.deliver(.push(title: "first", message: "", id: "a")) }
        await sender.waitUntilFirstSendStarted()
        let second = Task { await queue.deliver(.push(title: "second", message: "", id: "b")) }
        // the second hand-over reaches the queue while the first send is still blocked
        while await queue.handedOver < 2 { await Task.yield() }
        await sender.openGate()
        await first.value
        await second.value

        #expect(await sender.titles == ["first", "second"])
    }

    @Test("a failed send is logged and the next delivery still leaves")
    func failureDoesNotBlockQueue() async {
        let sender = GatedSender(failFirst: true)
        await sender.openGate()
        let queue = DeliveryQueue(sender: sender)

        await queue.deliver(.push(title: "fails", message: "", id: "a"))
        await queue.deliver(.push(title: "works", message: "", id: "b"))

        #expect(await sender.titles == ["fails", "works"])
        #expect(await queue.lastPushDate(id: "a") == nil)
        #expect(await queue.lastPushDate(id: "b") != nil)
    }

    @Test("every delivery kind reaches the sender with the caller's content")
    func allKindsReachSender() async {
        let recorder = RecordingNotificationSender()
        let queue = DeliveryQueue(sender: recorder)
        let state = WindowContentState(sortedWindows: [], outdoorTemperature: 3)
        let options = LiveActivityOptions(alert: nil, staleDate: Date(timeIntervalSince1970: 0), priority: .low)

        await queue.deliver(.liveActivity(contentState: state, activityName: WindowContentState.activityTypeName, options: options))
        await queue.deliver(.endLiveActivities(activityType: WindowContentState.activityTypeName))
        await queue.deliver(.push(title: "t", message: "m", id: "i", category: "c"))

        #expect(await recorder.events == [
            .liveActivity(.init(contentState: state, options: options)),
            .end(activityType: WindowContentState.activityTypeName),
            .notification(title: "t", message: "m", category: "c")
        ])
    }
}

private actor GatedSender: NotificationSender {
    private(set) var titles: [String] = []
    private var gateIsOpen = false
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private let failFirst: Bool

    struct Failure: Error {}

    init(failFirst: Bool = false) {
        self.failFirst = failFirst
    }

    func waitUntilFirstSendStarted() async {
        if !titles.isEmpty { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func openGate() {
        gateIsOpen = true
        gateWaiters.forEach { $0.resume() }
        gateWaiters = []
    }

    func sendNotification(title: String, message: String, id: String, category: String?) async throws {
        titles.append(title)
        startWaiters.forEach { $0.resume() }
        startWaiters = []
        if !gateIsOpen {
            await withCheckedContinuation { gateWaiters.append($0) }
        }
        if failFirst && titles.count == 1 { throw Failure() }
    }

    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState,
                                                                       activityName: String,
                                                                       options: LiveActivityOptions) async {}
    func endAllLiveActivities(ofActivityType activityType: String) async {}
}

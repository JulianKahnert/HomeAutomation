//
//  WindowProjectionLaneTests.swift
//  HomeAutomationKitTests
//

import Foundation
@testable import HAApplicationLayer
@testable import HAImplementations
import HAModels
import Testing

/// Holds the first Live Activity send open until it is released, like a slow APNS answer.
private actor SlowSender: NotificationSender {
    private(set) var events: [RecordingNotificationSender.Event] = []
    private var sendsStarted = 0
    private var gate: CheckedContinuation<Void, Never>?
    private var released = false

    func release() {
        released = true
        gate?.resume()
        gate = nil
    }

    func waitUntilFirstSendStarted() async {
        while sendsStarted == 0 { try? await Task.sleep(for: .milliseconds(1)) }
    }

    func waitForEvents(_ count: Int) async {
        while events.count < count { try? await Task.sleep(for: .milliseconds(1)) }
    }

    func sendNotification(title: String, message: String, id: String, category: String?) async throws {}

    nonisolated func clearNotification(id: String) async throws {}

    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState,
                                                                       activityName: String,
                                                                       options: LiveActivityOptions) async {
        sendsStarted += 1
        if sendsStarted == 1, !released {
            await withCheckedContinuation { gate = $0 }
        }
        guard let state = contentState as? WindowContentState else { return }
        events.append(.liveActivity(.init(contentState: state, options: options)))
    }

    func endAllLiveActivities(ofActivityType activityType: String) async {
        events.append(.end(activityType: activityType))
    }
}

@Suite("WindowProjection runs every trigger to its end")
struct WindowProjectionLaneTests {
    private let sender = SlowSender()
    private let manager: HomeManager
    private let service: AutomationService
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() async throws {
        manager = await HomeManager(getAdapter: { nil },
                                    storageRepo: MockStorageRepository(),
                                    notificationSender: sender,
                                    location: Location(latitude: 52.52, longitude: 13.405))
        service = try AutomationService(using: manager, runs: InMemoryAutomationRunRepository(), automations: [WindowProjection()])
    }

    private func deadlineId(_ name: String) -> EntityId {
        .serverOwned(name: "Küche/\(name)", characteristic: .deadline)
    }

    /// Reports the deadline and hands the change to the service, like the event loop does.
    private func report(_ deadline: Deadline, _ name: String) async throws {
        let id = deadlineId(name)
        await manager.report(id, value: .text(deadline.text))
        let item = try #require(await manager.states(of: CharacteristicsType.deadline.valueKind).first { $0.entityId == id })
        await service.trigger(with: .change(entity: item))
    }

    @Test("a window going überschritten while another update is still sending still gets its alert")
    func overdueDuringASlowSend() async throws {
        try await report(.running(until: start.addingTimeInterval(600)), "A")
        await sender.waitUntilFirstSendStarted()

        try await report(.running(until: start.addingTimeInterval(1_200)), "B")
        try await report(.overdue(since: start.addingTimeInterval(1_200)), "B")
        await sender.release()
        await service.waitUntilIdle()

        let alerts = await sender.events.compactMap { event -> LiveActivityOptions.Alert? in
            if case let .liveActivity(update) = event { return update.options.alert }
            return nil
        }
        #expect(alerts == [LiveActivityOptions.Alert(title: "Fenster schließen", body: "Küche: B")])
    }

    @Test("closing the last window while an update is still sending ends the activity")
    func closingTheLastWindowDuringASlowSend() async throws {
        try await report(.running(until: start.addingTimeInterval(600)), "A")
        await sender.waitUntilFirstSendStarted()

        try await report(.none, "A")
        await sender.release()
        await service.waitUntilIdle()

        #expect(await sender.events.last == .end(activityType: WindowContentState.activityTypeName))
    }
}

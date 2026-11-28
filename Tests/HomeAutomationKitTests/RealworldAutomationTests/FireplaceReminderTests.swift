//
//  FireplaceReminderTests.swift
//  HomeAutomationKitTests
//

import Foundation
@testable import HAImplementations
import HAModels
import Testing

@Suite("FireplaceReminder automation")
@HomeManagerActor
struct FireplaceReminderTests {
    private let sensor = EntityId(placeId: "Keller", name: "Raumsensor", characteristicsName: nil, characteristic: .temperatureSensor)
    private let homeManager = MockHomeAdapter()
    private let now = Date()
    private let minute: TimeInterval = 60

    private func reading(_ celsius: Double, minutesAgo: Double) -> EntityStorageItem {
        EntityStorageItem(entityId: sensor, timestamp: now.addingTimeInterval(-minutesAgo * minute), temperatureInC: Measurement(value: celsius, unit: .celsius))
    }

    /// Feeds the readings in order into the history and returns the newest as the change event.
    private func feed(_ readings: [EntityStorageItem]) -> HomeEvent {
        homeManager.storageItems.append(contentsOf: readings)
        return .change(entity: readings.last!)
    }

    private func reminder() -> FireplaceReminder {
        FireplaceReminder(roomSensor: sensor)
    }

    @Test("A rise of the threshold within the window triggers")
    func risesEnough() async throws {
        let event = feed([reading(18.0, minutesAgo: 25), reading(19.0, minutesAgo: 0)])

        #expect(try await reminder().shouldTrigger(with: event, using: homeManager))
    }

    @Test("A smaller rise does not trigger")
    func risesTooLittle() async throws {
        let event = feed([reading(18.0, minutesAgo: 25), reading(18.9, minutesAgo: 0)])

        #expect(try await !reminder().shouldTrigger(with: event, using: homeManager))
    }

    @Test("A rise slower than the window does not trigger")
    func risesTooSlowly() async throws {
        let event = feed([reading(17.0, minutesAgo: 120), reading(18.5, minutesAgo: 40), reading(19.0, minutesAgo: 0)])

        #expect(try await !reminder().shouldTrigger(with: event, using: homeManager))
    }

    @Test("A fall does not trigger")
    func falls() async throws {
        let event = feed([reading(21.0, minutesAgo: 25), reading(19.0, minutesAgo: 0)])

        #expect(try await !reminder().shouldTrigger(with: event, using: homeManager))
    }

    @Test("Another entity does not trigger")
    func otherEntity() async throws {
        let other = EntityStorageItem(entityId: EntityId(placeId: "Keller", name: "Anderer", characteristicsName: nil, characteristic: .temperatureSensor),
                                      temperatureInC: Measurement(value: 30, unit: .celsius))

        #expect(try await !reminder().shouldTrigger(with: .change(entity: other), using: homeManager))
        #expect(try await !reminder().shouldTrigger(with: .sunrise, using: homeManager))
    }

    @Test("No push while the fireplace is already on")
    func fireplaceOn() async throws {
        homeManager.fireplaceSwitches.append(FireplaceSwitch(timestamp: now.addingTimeInterval(-600), isOn: true))
        let event = feed([reading(18.0, minutesAgo: 25), reading(20.0, minutesAgo: 0)])

        #expect(try await !reminder().shouldTrigger(with: event, using: homeManager))
    }

    @Test("A fireplace that is off does not hold the push back")
    func fireplaceOff() async throws {
        homeManager.fireplaceSwitches += [FireplaceSwitch(timestamp: now.addingTimeInterval(-1200), isOn: true), FireplaceSwitch(timestamp: now.addingTimeInterval(-600), isOn: false)]
        let event = feed([reading(18.0, minutesAgo: 25), reading(20.0, minutesAgo: 0)])

        #expect(try await reminder().shouldTrigger(with: event, using: homeManager))
    }

    @Test("The push asks with the fireplace category and never switches the fireplace")
    func sendsAskPush() async throws {
        try await reminder().execute(using: homeManager)

        let push = try #require(homeManager.sentNotifications.first)
        #expect(push.title == "Kamin an?")
        #expect(push.message == "Heizkörper ausschalten")
        #expect(push.category == Fireplace.notificationCategory)
        #expect(push.id == Fireplace.reminderNotificationId)
        #expect(homeManager.performedActions.isEmpty)
    }

    @Test("After a push the next one waits for the rate limit")
    func rateLimit() async throws {
        let automation = reminder()
        let event = feed([reading(18.0, minutesAgo: 25), reading(20.0, minutesAgo: 0)])
        try await automation.execute(using: homeManager)

        #expect(try await !automation.shouldTrigger(with: event, using: homeManager))
    }

    @Test("A second push within two hours of the last one is blocked, one after two hours is sent")
    func rateLimitIsTwoHours() async throws {
        let automation = reminder()
        let event = feed([reading(18.0, minutesAgo: 25), reading(20.0, minutesAgo: 0)])

        homeManager.notificationDates[Fireplace.reminderNotificationId] = now.addingTimeInterval(-119 * minute)
        #expect(try await !automation.shouldTrigger(with: event, using: homeManager))

        homeManager.notificationDates[Fireplace.reminderNotificationId] = now.addingTimeInterval(-121 * minute)
        #expect(try await automation.shouldTrigger(with: event, using: homeManager))
    }

    @Test("The rate limit follows the configured interval")
    func rateLimitFollowsConfiguration() async throws {
        let automation = FireplaceReminder(roomSensor: sensor, minInterval: 600)
        let event = feed([reading(18.0, minutesAgo: 25), reading(20.0, minutesAgo: 0)])

        homeManager.notificationDates[Fireplace.reminderNotificationId] = now.addingTimeInterval(-9 * minute)
        #expect(try await !automation.shouldTrigger(with: event, using: homeManager))
        homeManager.notificationDates[Fireplace.reminderNotificationId] = now.addingTimeInterval(-11 * minute)
        #expect(try await automation.shouldTrigger(with: event, using: homeManager))
    }

    @Test("The end push of the fireplace does not count against the rate limit")
    func otherPushIgnored() async throws {
        await homeManager.deliver(.push(title: "Kamin aus", message: "", id: Fireplace.notificationId))
        let event = feed([reading(18.0, minutesAgo: 25), reading(20.0, minutesAgo: 0)])

        #expect(try await reminder().shouldTrigger(with: event, using: homeManager))
    }

    @Test("Threshold, window and rate limit are configurable and survive the configuration JSON")
    func codable() throws {
        let custom = FireplaceReminder(roomSensor: sensor, riseInC: 2, window: 600, minInterval: 60)
        let decoded = try JSONDecoder().decode(AnyAutomation.self, from: JSONEncoder().encode(AnyAutomation.create(from: custom)))

        let result = try #require(decoded.automation as? FireplaceReminder)
        #expect(result.riseInC == 2)
        #expect(result.window == 600)
        #expect(result.minInterval == 60)
        #expect(Set(result.getEntityIds()) == [sensor])
        #expect(FireplaceReminder(roomSensor: sensor).riseInC == 1.0)
        #expect(FireplaceReminder(roomSensor: sensor).window == 30 * 60)
        #expect(FireplaceReminder(roomSensor: sensor).minInterval == 2 * 3600)
    }
}

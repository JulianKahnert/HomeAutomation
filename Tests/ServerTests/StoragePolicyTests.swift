//
//  StoragePolicyTests.swift
//  HomeAutomation
//

import Foundation
@testable import HAModels
@testable import Server
import Testing

struct StoragePolicyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000 + 1_234) // not on an hour boundary

    // MARK: - rule table

    @Test(arguments: [CharacteristicsType.temperatureSensor, .targetTemperature, .heatingMode, .valvePosition, .heating, .valve,
                      .relativeHumiditySensor, .contactSensor, .batterySensor, .lock, .motionSensor, .switcher,
                      .brightness, .colorTemperature, .color, .airQualitySensor, .pmDensitySensor])
    func keepsRawForeverWithoutRollupOrDeadBand(_ type: CharacteristicsType) {
        let policy = StoragePolicy.policy(for: type)
        #expect(policy.rawRetentionDays == nil)
        #expect(policy.rollup == .none)
        #expect(policy.deadBand == nil)
    }

    @Test(arguments: [CharacteristicsType.lightSensor, .carbonDioxideSensorId])
    func rollsUpLuxAndCO2HourlyAfter90Days(_ type: CharacteristicsType) {
        let policy = StoragePolicy.policy(for: type)
        #expect(policy.rawRetentionDays == 90)
        #expect(policy.rollup == .hourly)
        #expect(policy.kind == .analog)
    }

    @Test func co2HasDeadBandAndTreatsZeroAsError() throws {
        let policy = StoragePolicy.policy(for: .carbonDioxideSensorId)
        #expect(policy.deadBand == StoragePolicy.DeadBand(threshold: .absolute(25), maxInterval: .minutes(15)))
        let range = try #require(policy.validRange)
        #expect(!range.contains(0))
        #expect(range.contains(420))
        #expect(StoragePolicy.policy(for: .lightSensor).validRange?.contains(0) == true)
    }

    @Test func heatingFieldsAreStates() {
        for type in [CharacteristicsType.targetTemperature, .heatingMode, .valvePosition, .heating, .valve] {
            #expect(StoragePolicy.policy(for: type).kind == .state)
        }
        #expect(StoragePolicy.policy(for: .airQualitySensor).kind == .enumeration)
    }

    @Test(arguments: CharacteristicsType.allCases)
    func rollupAndDeadBandAlwaysNameTheirValueColumn(_ type: CharacteristicsType) {
        let policy = StoragePolicy.policy(for: type)
        if policy.rollup != .none || policy.deadBand != nil {
            #expect(policy.valueColumn != nil)
            #expect(policy.kind == .analog)
        }
        if policy.rollup != .none {
            #expect(policy.rawRetentionDays != nil)
        }
    }

    @Test func unknownTypeIsKeptRawForever() {
        #expect(StoragePolicy.policy(forRawType: "fineDustSensorV2") == StoragePolicy.unknown)
        #expect(StoragePolicy.unknown.rawRetentionDays == nil)
        #expect(StoragePolicy.unknown.rollup == .none)
        #expect(StoragePolicy.policy(forRawType: "carbonDioxideSensorId") == StoragePolicy.policy(for: .carbonDioxideSensorId))
    }

    // MARK: - dead band

    @Test func absoluteDeadBandStoresOnlyLargeChangesOrAfterMaxInterval() {
        let band = StoragePolicy.DeadBand(threshold: .absolute(25), maxInterval: .minutes(15))
        let last = (value: 800.0, timestamp: now)
        #expect(band.shouldStore(800, at: now, lastStored: nil))
        #expect(!band.shouldStore(824, at: now.addingTimeInterval(60), lastStored: last))
        #expect(!band.shouldStore(776.5, at: now.addingTimeInterval(60), lastStored: last))
        #expect(band.shouldStore(825, at: now.addingTimeInterval(60), lastStored: last))
        #expect(band.shouldStore(775, at: now.addingTimeInterval(60), lastStored: last))
        #expect(!band.shouldStore(800, at: now.addingTimeInterval(14 * 60 + 59), lastStored: last))
        #expect(band.shouldStore(800, at: now.addingTimeInterval(15 * 60), lastStored: last))
        #expect(band.shouldStore(0, at: now.addingTimeInterval(1), lastStored: last))
    }

    @Test func relativeDeadBandScalesWithTheLastValue() {
        let band = StoragePolicy.DeadBand(threshold: .relative(0.1), maxInterval: .hours(1))
        #expect(!band.shouldStore(109, at: now, lastStored: (100, now)))
        #expect(band.shouldStore(110, at: now, lastStored: (100, now)))
        #expect(!band.shouldStore(1_090, at: now, lastStored: (1_000, now)))
        #expect(band.shouldStore(90, at: now, lastStored: (100, now)))
    }

    // MARK: - cleanup and rollup selection

    @Test func cleanupDeletesNoTypeThatIsKeptForeverOrRolledUp() {
        let types = StoragePolicy.cleanupCutoffs(now: now).map(\.type)
        // Today every type without a rollup is kept forever, so the cleanup deletes no entity rows.
        #expect(types.isEmpty)
    }

    @Test func rollupSelectsLuxAndCO2WithAnHourAlignedCutoff90DaysBack() throws {
        let targets = StoragePolicy.rollupCutoffs(now: now)
        #expect(Set(targets.map(\.type)) == [.lightSensor, .carbonDioxideSensorId])
        let co2 = try #require(targets.first { $0.type == .carbonDioxideSensorId })
        #expect(co2.column == .carbonDioxideSensorId)
        #expect(co2.before.timeIntervalSince1970.truncatingRemainder(dividingBy: 3600) == 0)
        let exact = now.addingTimeInterval(-90 * 86_400)
        #expect(co2.before <= exact)
        #expect(exact.timeIntervalSince(co2.before) < 3600)
    }

    @Test func cleanupJobDeletesOnlyRunsAndRollupJobCondensesLuxAndCO2() async {
        let store = RecordingRetentionStore()
        let runs = RecordingRunDeleter()
        let job = DatabaseCleanupJob(entities: store,
                                     automationRuns: runs,
                                     noisyEntityWarner: NoisyEntityWarner(notificationSender: RecordingNotificationSender()))

        await job.performCleanup(now: now)
        await EntityRollupJob(entities: store).rollUpOnce(now: now)

        #expect(await store.deletedTypes.isEmpty)
        #expect(Set(await store.rolledUpTypes) == [.lightSensor, .carbonDioxideSensorId])
        #expect(await runs.deletedBefore == [now.addingTimeInterval(-30 * 86_400)])
    }

    // MARK: - noise guard

    @Test func warnsOncePerNoisyEntityAndDay() async throws {
        let store = RecordingRetentionStore(counts: [
            EntityRowCount(placeId: "Kueche", serviceName: "Air", characteristicType: "carbonDioxideSensorId", rows: 2_300),
            EntityRowCount(placeId: "Flur", serviceName: "Lux", characteristicType: "someFutureType", rows: 600)
        ])
        let sender = RecordingNotificationSender()
        let warner = NoisyEntityWarner(notificationSender: sender)

        try await warner.check(store, now: now)
        try await warner.check(store, now: now.addingTimeInterval(23 * 3600))
        #expect(await sender.ids.count == 2)
        #expect(await store.countQueries.first?.limit == 500)
        #expect(await store.countQueries.first?.since == now.addingTimeInterval(-86_400))
        let message = try #require(await sender.messages.first)
        #expect(message.contains("2300") && message.contains("dead band"))

        try await warner.check(store, now: now.addingTimeInterval(24 * 3600))
        #expect(await sender.ids.count == 4)
        #expect(Set(await sender.ids).count == 2)
    }
}

private actor RecordingRetentionStore: EntityRetentionStore {
    private let counts: [EntityRowCount]
    private(set) var deletedTypes: [CharacteristicsType] = []
    private(set) var rolledUpTypes: [CharacteristicsType] = []
    private(set) var countQueries: [(limit: Int, since: Date)] = []

    init(counts: [EntityRowCount] = []) {
        self.counts = counts
    }

    func deleteEntries(ofType type: CharacteristicsType, olderThan date: Date) async throws {
        deletedTypes.append(type)
    }

    func rollUpHourly(type: CharacteristicsType, column: StoragePolicy.ValueColumn, validRange: ClosedRange<Double>?, olderThan date: Date) async throws {
        rolledUpTypes.append(type)
    }

    func entitiesWithRowCount(above limit: Int, since date: Date) async throws -> [EntityRowCount] {
        countQueries.append((limit, date))
        return counts.filter { $0.rows > limit }
    }
}

private actor RecordingNotificationSender: NotificationSender {
    private(set) var ids: [String] = []
    private(set) var messages: [String] = []

    func sendNotification(title: String, message: String, id: String) async throws {
        ids.append(id)
        messages.append(message)
    }

    func clearNotification(id: String) async throws {}
    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState, activityName: String) async {}
    func endAllLiveActivities(ofActivityType activityType: String) async {}
}

private actor RecordingRunDeleter: AutomationRunRepository {
    private(set) var deletedBefore: [Date] = []

    func add(_ run: AutomationRun) async throws {}
    func finish(_ id: UUID, outcome: AutomationRun.Outcome, endedAt: Date, errorDescription: String?) async throws {}
    func runs(for automationName: String, startDate: Date?, endDate: Date?, limit: Int) async throws -> [AutomationRun] { [] }
    func latestRuns(since date: Date, limit: Int) async throws -> [AutomationRun] { [] }
    func latestRunPerAutomation() async throws -> [String: AutomationRun] { [:] }
    func markRunningAsInterrupted() async throws {}
    func deleteRuns(olderThan date: Date) async throws {
        deletedBefore.append(date)
    }
}

//
//  AppStorage.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 01.02.25.
//

import Adapter
import HAApplicationLayer
import HAImplementations
import HAModels
import Shared
import StarActorSystem
import Vapor

private let homeEvents = AsyncStream.makeStream(of: HomeInput.self)

 extension Application {
     var entityStorageDbRepository: EntityStorageDbRepository {
         EntityStorageDbRepository(database: { self.db })
     }

     var homekitInventoryRepository: HomekitInventoryDbRepository {
         HomekitInventoryDbRepository(database: { self.db })
     }

     var journalRepository: JournalDbRepository {
         JournalDbRepository(database: { self.db })
     }

    private struct HomeEventsStreamKey: StorageKey {
        typealias Value = AsyncStream<HomeInput>
    }

    var homeEventsStream: AsyncStream<HomeInput> {
        get {
            self.storage[HomeEventsStreamKey.self] ?? homeEvents.stream
        }
        set {
            self.storage[HomeEventsStreamKey.self] = newValue
        }
    }

     private struct HomeEventsContinuationKey: StorageKey {
         typealias Value = AsyncStream<HomeInput>.Continuation
     }

     var homeEventsContinuation: AsyncStream<HomeInput>.Continuation {
         get {
             self.storage[HomeEventsContinuationKey.self] ?? homeEvents.continuation
         }
         set {
             self.storage[HomeEventsContinuationKey.self] = newValue
         }
     }

     private struct StarActorSystemKey: StorageKey {
         typealias Value = StarActorSystem
     }

     var starActorSystem: StarActorSystem {
         get {
             self.storage[StarActorSystemKey.self]!
         }
         set {
             self.storage[StarActorSystemKey.self] = newValue
         }
     }

     private struct HomeManagerKey: StorageKey {
         typealias Value = HomeManagable
     }

     var homeManager: HomeManagable {
         get {
             self.storage[HomeManagerKey.self]!
         }
         set {
             self.storage[HomeManagerKey.self] = newValue
         }
     }

     private struct AutomationServiceKey: StorageKey {
         typealias Value = AutomationService
     }

     var automationService: AutomationService {
         get {
             self.storage[AutomationServiceKey.self]!
         }
         set {
             self.storage[AutomationServiceKey.self] = newValue
         }
     }

     private struct StorageReaderKey: StorageKey {
         typealias Value = any StorageRepository
     }

     /// Where the API layer reads entity states and history: the database, unless a test brings its own.
     var storageReader: any StorageRepository {
         get {
             self.storage[StorageReaderKey.self] ?? entityStorageDbRepository
         }
         set {
             self.storage[StorageReaderKey.self] = newValue
         }
     }

     private struct JournalReaderKey: StorageKey {
         typealias Value = any JournalStore
     }

     /// Where the API layer reads runs, commands and pushes.
     var journalReader: any JournalStore {
         get {
             self.storage[JournalReaderKey.self] ?? journalRepository
         }
         set {
             self.storage[JournalReaderKey.self] = newValue
         }
     }

     private struct CommandPortKey: StorageKey {
         typealias Value = any CommandPort
     }

     /// The API layer's only way to write into the core: commands enter the event loop through the event stream.
     var commandPort: any CommandPort {
         get {
             self.storage[CommandPortKey.self] ?? EventFlowCommandPort(sink: homeEventSink, unknownEntities: { [self] entityIds in
                 // A server-owned entity is not in HomeKit, so the adapter cannot confirm it (ADR-009); with nothing
                 // else to check the adapter need not be online either.
                 let homeKitEntityIds = entityIds.filter { !$0.isServerOwned }
                 guard !homeKitEntityIds.isEmpty else { return [] }
                 let found = try await homeManager.getAllEntitiesLive()
                 return homeKitEntityIds.subtracting(found.map(\.entityId))
             })
         }
         set {
             self.storage[CommandPortKey.self] = newValue
         }
     }

     private struct ConfigReaderKey: StorageKey {
         typealias Value = any ConfigReading
     }

     /// Where the API layer reads the deployed configuration.
     var configReader: any ConfigReading {
         get {
             self.storage[ConfigReaderKey.self] ?? ConfigDbRepository(database: { self.db })
         }
         set {
             self.storage[ConfigReaderKey.self] = newValue
         }
     }

     private struct EventLoopGaugeKey: StorageKey {
         typealias Value = EventLoopGauge
     }

     var eventLoopGauge: EventLoopGauge {
         if let gauge = self.storage[EventLoopGaugeKey.self] { return gauge }
         let gauge = EventLoopGauge()
         self.storage[EventLoopGaugeKey.self] = gauge
         return gauge
     }

     /// Where producers yield events, so the gauge sees how long they wait.
     var homeEventSink: HomeEventSink {
         HomeEventSink(continuation: homeEventsContinuation, gauge: eventLoopGauge)
     }

     private struct SchedulerKey: StorageKey {
         typealias Value = Scheduler
     }

     var scheduler: Scheduler? {
         get {
             self.storage[SchedulerKey.self]
         }
         set {
             self.storage[SchedulerKey.self] = newValue
         }
     }

     private struct HomeEventReceiverKey: StorageKey {
         typealias Value = HomeEventReceiver
     }

     var homeEventReceiver: HomeEventReceiver {
         get {
             self.storage[HomeEventReceiverKey.self]!
         }
         set {
             self.storage[HomeEventReceiverKey.self] = newValue
         }
     }

     private struct HomeAutomationConfigControllerKey: StorageKey {
         typealias Value = HomeAutomationConfigService
     }

     var homeAutomationConfigService: HomeAutomationConfigService {
         get {
             self.storage[HomeAutomationConfigControllerKey.self]!
         }
         set {
             self.storage[HomeAutomationConfigControllerKey.self] = newValue
         }
     }

     private struct AuthTokenKey: StorageKey {
         typealias Value = String
     }

     var authToken: String {
         get {
             self.storage[AuthTokenKey.self]!
         }
         set {
             self.storage[AuthTokenKey.self] = newValue
         }
     }

     private struct AuthDisabledKey: StorageKey {
         typealias Value = Bool
     }

     var authDisabled: Bool {
         get {
             self.storage[AuthDisabledKey.self] ?? false
         }
         set {
             self.storage[AuthDisabledKey.self] = newValue
         }
     }
 }

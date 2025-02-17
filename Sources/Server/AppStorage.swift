//
//  AppStorage.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 01.02.25.
//

import HAImplementations
import HAModels
import Vapor

private let homeEvents = AsyncStream.makeStream(of: HomeEvent.self)

 extension Application {
     var entityStorageDbRepository: EntityStorageDbRepository {
         EntityStorageDbRepository(database: db)
     }

    private struct HomeEventsStreamKey: StorageKey {
        typealias Value = AsyncStream<HomeEvent>
    }

    var homeEventsStream: AsyncStream<HomeEvent> {
        get {
            self.storage[HomeEventsStreamKey.self] ?? homeEvents.stream
        }
        set {
            self.storage[HomeEventsStreamKey.self] = newValue
        }
    }

     private struct HomeEventsContinuationKey: StorageKey {
         typealias Value = AsyncStream<HomeEvent>.Continuation
     }

     var homeEventsContinuation: AsyncStream<HomeEvent>.Continuation {
         get {
             self.storage[HomeEventsContinuationKey.self] ?? homeEvents.continuation
         }
         set {
             self.storage[HomeEventsContinuationKey.self] = newValue
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
 }

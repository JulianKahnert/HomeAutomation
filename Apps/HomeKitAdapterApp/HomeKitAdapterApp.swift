//
//  HomeKitAdapterApp.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 28.05.24.
//

import HAImplementations
import HAModels
import Logging
import LoggingOSLog
import SwiftUI

let log = Logger(label: "HomeKitAdapterApp")
@MainActor var commandReceiver: HomeKitCommandReceiver!

@main
struct HomeKitAdapterApp: App {
    @AppStorage("ShouldCrashIfActorSystemInitFails") private var shouldCrashIfActorSystemInitFails = false
    @State private var logTask: Task<Void, Never>?
    @State private var entities: [EntityStorageItem] = []

    init() {
        let stream = FileLogHandler.FileHandlerOutputStream(basePath: URL.documentsDirectory)
        LoggingSystem.bootstrap { label in
            let handlers: [LogHandler] = [
                FileLogHandler(label: label, stream: stream),
                LoggingOSLog(label: label)
            ]
            var mpxHandler = MultiplexLogHandler(handlers)
            mpxHandler.logLevel = .debug
            return MultiplexLogHandler(handlers)
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView(shouldCrashIfActorSystemInitFails: $shouldCrashIfActorSystemInitFails, entities: $entities)
            }
            .task {
                log.info("runloop task called")

                // do not start run loop when running in preview canvas
                guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

                try! await Task.sleep(for: .seconds(1))
                let actorSystem = await CustomActorSystem(nodeId: .homeKitAdapter, port: 7777)

                let (entityStream, entityStreamContinuation) = AsyncStream.makeStream(
                    of: EntityStorageItem.self, bufferingPolicy: .unbounded)
                let adapter = HomeKitAdapter(
                    entityStream: entityStream,
                    entityStreamContinuation: entityStreamContinuation)

                commandReceiver = actorSystem.makeLocalActor(actorId: .homeKitCommandReceiver) { system in
                    HomeKitCommandReceiver(actorSystem: system, adapter: adapter)
                }
                _ = await actorSystem.checkIn(actorId: .homeKitCommandReceiver, commandReceiver)

                if shouldCrashIfActorSystemInitFails {
                    try! await actorSystem.waitForThisNode(is: .up, within: .seconds(10))
                }

                var receiver: HomeEventReceiver?
                Task {
                    for await foundReceiver in await actorSystem.listing(of: .homeEventReceiver) {
                        log.info("Get new HomeEventReceiver")
                        receiver = foundReceiver
                    }
                }

                for await entity in entityStream {
                    // saving the data locally for the ui
                    self.entities = self.entities.suffix(99) + [entity]

                    do {
                        if receiver == nil {
                            receiver = await actorSystem.lookup(.homeEventReceiver)
                            if receiver == nil {
                                log.error("Failed to resolve HomeEventReceiver actor")
                            }
                        }

                        // this might be very slow, when no server is connected
                        try await receiver?.process(event: .change(entity: entity))
                    } catch {
                        log.error("Failed to process event: \(error)")
                    }
                }
            }
        }
    }
}

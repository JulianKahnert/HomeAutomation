//
//  FlowKit Adapter.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 28.05.24.
//

import HAImplementations
import HAModels
import Logging
import LoggingOSLog
import SwiftUI

@MainActor var commandReceiver: HomeKitCommandReceiver!

@main
struct FlowKitApp {
    /// Entrypoint of the app
    static func main() {

        // we use this workaround to initialize the logging system before anything else is constructed
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

        // start the app
        FlowKitAdapter.main()
    }
}

struct FlowKitAdapter: App {
    static let log = Logger(label: "FlowKit Adapter")
    @AppStorage("ShouldCrashIfActorSystemInitFails") private var shouldCrashIfActorSystemInitFails = false
    @State private var logTask: Task<Void, Never>?
    @State private var entities: [EntityStorageItem] = []

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView(shouldCrashIfActorSystemInitFails: $shouldCrashIfActorSystemInitFails, entities: $entities)
            }
            .task {
                Self.log.info("runloop task called")

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
                        Self.log.info("Get new HomeEventReceiver")
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
                                Self.log.error("Failed to resolve HomeEventReceiver actor")
                            }
                        }

                        // this might be very slow, when no server is connected
                        try await receiver?.process(event: .change(entity: entity))
                    } catch {
                        Self.log.error("Failed to process event: \(error)")
                    }
                }
            }
        }
    }
}

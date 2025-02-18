//
//  HomeKitAdapterApp.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 28.05.24.
//

import HAImplementations
import HAModels
import Logging
import SwiftUI

let log = Logger(label: "HomeKitAdapterApp")

@main
struct HomeKitAdapterApp: App {
    @State private var logIntervall: LogIntervall = .off
    @State private var logTask: Task<Void, Never>?
    @State private var entities: [EntityStorageItem] = []

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView(entities: $entities)
            }
            .onChange(of: logIntervall, initial: true) { _, logIntervall in
                logIntervallChanged(to: logIntervall)
            }
            .task {
                log.info("runloop task called")
                let actorSystem = await ActorSystem(nodeId: .homeKitAdapter, port: 7777)

                // do not start run loop when running in preview canvas
                guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

                let (entityStream, entityStreamContinuation) = AsyncStream.makeStream(
                    of: EntityStorageItem.self, bufferingPolicy: .unbounded)
                let adapter = HomeKitAdapter(
                    entityStream: entityStream,
                    entityStreamContinuation: entityStreamContinuation)

                #warning("TODO: save this actor properly somewhere else to keep a reference to it")
                let commandReceiver = HomeKitCommandReceiver(actorSystem: actorSystem.webSocketActorSystem, adapter: adapter)
                _ = await actorSystem.checkIn(actorId: .homeKitCommandReceiver, commandReceiver)
                try! await actorSystem.joined(within: .seconds(10))

                var receiver: HomeEventReceiver?
                for await entity in entityStream {
                    // saving the data locally for the ui
                    self.entities = self.entities.suffix(99) + [entity]

                    do {
                        if receiver == nil {
                            receiver = await actorSystem.resolve(.homeEventReceiver)
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
        .commands {
            CommandMenu("Logging") {
                ForEach(LogIntervall.allCases, id: \.self) { intervall in
                    Button(intervall.text) {
                        logIntervall = intervall
                    }
                }
            }
        }
    }

    private func logIntervallChanged(to logInterval: LogIntervall) {
        log.info("logging task called")

        logTask?.cancel()
        guard let duration = logIntervall.duration else {
            log.debug("skip logging")
            return
        }
        logTask = Task.detached(priority: .low) {
            #if canImport(OSLog)
            let logItemStorage = try! LogItemStorage()
            for await _ in Timer.publish(
                every: duration.timeInterval, on: .main, in: .common
            ).autoconnect().values {
                do {
                    try await logItemStorage.updateEntries()
                } catch {
                    log.critical("Failed to update log entries - error \(error)")
                    assertionFailure()
                }
            }
            #endif
        }
    }
}

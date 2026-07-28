//
//  FlowKit Adapter.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 28.05.24.
//

import Adapter
import Foundation
import HAImplementations
import HAModels
import Logging
import Shared
import StarActorSystem
import SwiftUI

@main
struct FlowKitApp {
    private static let log = Logger(label: "FlowKitAdapter")

    /// Entrypoint of the app
    static func main() {

        // we use this workaround to initialize the logging system before anything else is constructed
        initLogging(withFileLogging: true, logLevel: .debug)

        logStartupProvenance()

        // start the app
        FlowKitAdapter.main()
    }

    /// Logs the running build's version and binary build date at startup. The adapter is built and
    /// installed out-of-band from the server Docker image, so without this there is no way to tell
    /// from the logs which code (e.g. which connection fix) the deployed `.app` actually contains.
    private static func logStartupProvenance() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let buildDate: String = {
            guard let url = Bundle.main.executableURL,
                  let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let date = attrs[.modificationDate] as? Date else { return "unknown" }
            return ISO8601DateFormatter().string(from: date)
        }()
        Self.log.info("FlowKit Adapter starting — version \(version) (build \(build)), binary built \(buildDate)")
    }
}

struct FlowKitAdapter: App, Log {
    @AppStorage("ActorSystemServerAddress") private var serverAddress = ServerAddress(host: "localhost", port: 8080)
    @AppStorage("ServerAuthToken") private var serverAuthToken = ""
    @State private var connection: AdapterConnection?

    var body: some Scene {
        WindowGroup {
            ContentView(
                entities: connection?.entities ?? [],
                connectionStatus: connection?.connectionStatus ?? .connecting
            )
            .task(id: "\(serverAddress.rawValue)|\(serverAuthToken)") {
                Self.log.info("runloop task called for address: \(serverAddress)")

                // do not start run loop when running in preview canvas
                guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

                // Tear down a previously-created connection first (e.g. serverAddress or
                // token changed) so its transport loop stops before creating a new one.
                connection?.stop()
                connection = nil

                let newConnection = AdapterConnection(address: serverAddress, authToken: serverAuthToken)
                newConnection?.start()

                // Cancellation-safety: if this task was cancelled while setting up (e.g. the
                // address changed again), do not leak a half-initialized connection.
                guard !Task.isCancelled else {
                    newConnection?.stop()
                    return
                }
                connection = newConnection
            }
        }
    }
}

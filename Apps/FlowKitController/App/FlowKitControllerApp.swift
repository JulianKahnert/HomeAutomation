//
//  FlowKitControllerApp.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 22.02.25.
//

import AppIntents
import Controller
import Shared
import SwiftUI

@main
struct FlowKitApp {
    /// Entrypoint of the app
    static func main() {

        // we use this workaround to initialize the logging system before anything else is constructed
        initLogging(withFileLogging: true, logLevel: .debug)

        // start the app
        FlowKitControllerApp.main()
    }
}

struct FlowKitControllerApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    #else
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// The intents of the Controller module (the answers of the fireplace question) for the app's metadata: a Live
/// Activity intent runs in the app's process.
struct FlowKitControllerAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [ControllerAppIntents.self] }
}

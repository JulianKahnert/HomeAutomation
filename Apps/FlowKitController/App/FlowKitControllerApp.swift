//
//  FlowKitControllerApp.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 22.02.25.
//

import Controller
import Shared
import SwiftUI

@main
struct FlowKitApp {
    /// Entrypoint of the app
    static func main() {

        // we use this workaround to initialize the logging system before anything else is constructed
        initLogging(withFileLogging: false, logLevel: .debug)

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

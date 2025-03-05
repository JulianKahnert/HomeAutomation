//
//  FlowKitControllerApp.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 22.02.25.
//

import SwiftUI

@main
struct FlowKitControllerApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    #else
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
            }
        }
    }
}

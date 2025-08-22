//
//  ContentView.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 22.02.25.
//

import HAModels
import Logging
import SwiftUI
import UserNotifications

typealias Automation = Components.Schemas.Automation
extension Automation: Identifiable {
    var id: String { name }
}

extension Bool {
    var inverted: Bool { !self }
}

struct ContentView: View {
    private static let logger = Logger(label: "ContentView")

    @AppStorage(FlowKitClient.userDefaultsKey) private var url = URL(string: "http://0.0.0.0:8080/")!
    @Environment(AppState.self) var appState

    @State private var showSettings = false
    @State private var showLiveActivityData = false
    @State private var client: FlowKitClient!
    @State private var automations: [Automation] = []

    var body: some View {
        List {
            Section {
                ForEach(automations.filter(\.isRunning)) { automation in
                    NavigationLink(destination: {
                        AutomationView(client: client, automation: automation)
                    }, label: {
                        view(for: automation)
                    })
                }
            }
            Section {
                ForEach(automations.filter(\.isRunning.inverted)) { automation in
                    NavigationLink(destination: {
                        AutomationView(client: client, automation: automation)
                    }, label: {
                        view(for: automation)
                    })
                }
            }
        }
        #if canImport(ActivityKit)
        .popover(isPresented: $showLiveActivityData) {
            Group {
                if let activityViewState = appState.activityViewState {
                    WindowOpenLiveActivityView(contentState: activityViewState)
                } else {
                    ContentUnavailableView("No live activity data", systemImage: "chart.bar.horizontal.page")
                }
            }
        }
        #endif
        .navigationDestination(isPresented: $showSettings) {
            SettingsView(serverAddress: $url)
        }
        .navigationTitle(url.description)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem {
                Button("Preferences", systemImage: "gear") {
                    showSettings.toggle()
                }
            }
            #if canImport(ActivityKit)
            ToolbarItem {
                Button("Push Notification", systemImage: "app.badge") {
//                    appState.startLiveActivity()
                    showLiveActivityData.toggle()
                }
            }
            #endif
        }
        .refreshable {
            await updateData()
        }
        .onAppear {
            client = FlowKitClient(url: url)
            Task {
                await updateData()
            }
            requestRemoteNotificationsIfNeeded()
        }
        .onChange(of: url) { _, _ in
            client = FlowKitClient(url: url)
            Task {
                await updateData()
            }
        }
    }

    @ViewBuilder
    func view(for automation: Automation) -> some View {
        HStack {
            Text(automation.name)
                .foregroundStyle(automation.isRunning ? Color.green : Color.primary)
            Spacer()
            Image(systemName: "x.circle")
                .foregroundStyle(automation.isActive ? Color.clear : Color.red)
        }
    }

    func updateData() async {
        Self.logger.info("Update data ...")
        #if canImport(ActivityKit)
        await appState.fetchWindowState()
        #endif
        do {
            self.automations = try await client.getAutomations()
        } catch {
            self.automations = []
        }
    }

    private func requestRemoteNotificationsIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            if granted {
                DispatchQueue.main.async {
                    #if canImport(UIKit)
                    UIApplication.shared.registerForRemoteNotifications()
                    #else
                    NSApplication.shared.registerForRemoteNotifications()
                    #endif
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

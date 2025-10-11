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
    @Environment(\.scenePhase) var scenePhase

    @State private var showSettings = false
    @State private var showLiveActivityData = false
    @State private var client: FlowKitClient!

    @StateObject private var automationStore = AutomationStore.liveValue

    var body: some View {
        List {
            Section {
                ForEach(automationStore.automations.filter(\.isRunning)) { automation in
                    NavigationLink(destination: {
                        AutomationView(
                            client: client,
                            automation: automation,
                            onDataUpdate: { await updateData() }
                        )
                    }, label: {
                        view(for: automation)
                    })
                }
            }
            Section {
                ForEach(automationStore.automations.filter(\.isRunning.inverted)) { automation in
                    NavigationLink(destination: {
                        AutomationView(
                            client: client,
                            automation: automation,
                            onDataUpdate: { await updateData() }
                        )
                    }, label: {
                        view(for: automation)
                    })
                }
            }
        }
        #if os(iOS)
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
            #if os(iOS)
            ToolbarItem {
                Button("Push Notification", systemImage: "app.badge") {
//                    appState.startLiveActivity()
                    showLiveActivityData.toggle()
                }
                .badge(appState.activityViewState?.windowStates.count ?? 0)
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
        .onChange(of: scenePhase) { _, new in
            guard new == .active else { return }
            Task {
                await updateData()
            }
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
        #if os(iOS)
        await appState.fetchWindowState()
        #endif
        do {
            let fetchedAutomations = try await client.getAutomations()
            automationStore.updateAll(fetchedAutomations)
        } catch {
            automationStore.updateAll([])
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

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

    enum TabType {
        case automations
        case actions
        case settings
    }

    @AppStorage(FlowKitClient.userDefaultsKey) private var url = URL(string: "http://0.0.0.0:8080/")!
    @Environment(AppState.self) var appState
    @Environment(\.scenePhase) var scenePhase

    @State private var showLiveActivityData = false
    @State private var client: FlowKitClient!
    @State private var automations: [Automation] = []
    @State private var selectedTab: TabType = .automations

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Automations", systemImage: "gearshape.2", value: TabType.automations) {
                automationsTab
            }

            Tab("Actions", systemImage: "list.bullet", value: TabType.actions) {
                NavigationStack {
                    ActionsListView(client: client ?? FlowKitClient(url: url))
                }
            }

            Tab("Settings", systemImage: "gear", value: TabType.settings) {
                NavigationStack {
                    SettingsView(serverAddress: $url)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
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
    private var automationsTab: some View {
        NavigationStack {
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
            .navigationTitle(url.description)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
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

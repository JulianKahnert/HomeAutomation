//
//  ContentView.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 22.02.25.
//

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
    @AppStorage(FlowKitClient.userDefaultsKey) private var url = URL(string: "http://0.0.0.0:8080/")!
    @State private var showSettings = false
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
        }
        .refreshable {
            await updateAutomations()
        }
        .onAppear {
            client = FlowKitClient(url: url)
            Task {
                await updateAutomations()
            }
            requestRemoteNotificationsIfNeeded()
        }
        .onChange(of: url) { _, _ in
            client = FlowKitClient(url: url)
            Task {
                await updateAutomations()
            }
        }
    }

    @ViewBuilder
    func view(for automation: Automation) -> some View {
        HStack {
            Text(automation.name)
            Spacer()
            Image(systemName: "circle.fill")
                .foregroundStyle(automation.isRunning ? Color.green : Color.gray.opacity(0.3))
        }
    }

    func updateAutomations() async {
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

//
//  ContentView.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 22.02.25.
//

import SwiftUI

typealias Automation = Components.Schemas.Automation
extension Automation: Identifiable {
    var id: String { name }
}

extension Bool {
    var inverted: Bool { !self }
}

struct ContentView: View {
    @AppStorage("AutomationClientUrl") private var url = URL(string: "http://0.0.0.0:8080/")!
    @State private var showSettings = false
    @State private var client: AutomationClient!
    @State private var automations: [Automation] = []

    var body: some View {
        List {
            Section {
                ForEach(automations.filter(\.isRunning)) { automation in
                    view(for: automation)
                }
            }
            Section {
                ForEach(automations.filter(\.isRunning.inverted)) { automation in
                    view(for: automation)
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
            client = AutomationClient(url: url)
            Task {
                await updateAutomations()
            }
        }
        .onChange(of: url) { _, newValue in
            client = AutomationClient(url: url)
            Task {
                await updateAutomations()
            }
        }
    }

    @ViewBuilder
    func view(for automation: Automation) -> some View {
        VStack(alignment: .leading) {
            Text(automation.name)
            HStack {
                Image(systemName: "circle.fill")
                    .foregroundStyle(automation.isRunning ? Color.green : Color.gray.opacity(0.3))
                Spacer()
                Toggle("", isOn: Binding<Bool>(get: {
                    automation.isActive
                }, set: { value in
                    guard value != automation.isActive else { return }
                    Task {
                        await toggleActive(value, automationName: automation.name)
                    }
                }))
            }
        }
    }

    func updateAutomations() async {
        do {
            self.automations = try await client.getAutomations()
        } catch {
            self.automations = []
        }
    }

    func toggleActive(_ value: Bool, automationName: String) async {
        do {
            if value {
                try await client.activate(automation: automationName)
            } else {
                try await client.deactivate(automation: automationName)
            }
            self.automations = try await client.getAutomations()
        } catch {
            assertionFailure()
        }
    }
}

#Preview {
    ContentView()
}

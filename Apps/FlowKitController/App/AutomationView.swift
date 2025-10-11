//
//  AutomationView.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 22.02.25.
//

import SwiftUI

struct AutomationView: View {
    let client: FlowKitClient!
    let automation: Automation
    let onDataUpdate: () async -> Void

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Is Running")
                    Spacer()
                    Image(systemName: "circle.fill")
                        .foregroundStyle(automation.isRunning ? Color.green : Color.gray.opacity(0.3))
                }
            }
            Section {
                Toggle("Is Active", isOn: Binding<Bool>(get: {
                    automation.isActive
                }, set: { value in
                    guard value != automation.isActive else { return }
                    Task {
                        await toggleActive(value, automationName: automation.name)
                    }
                }))
            }

            Section {
                Button("Stop Automation") {
                    Task {
                        try! await client.stop(automation: automation.name)
                    }
                }
            }
        }
        .navigationTitle(automation.name)
    }

    func toggleActive(_ value: Bool, automationName: String) async {
        do {
            if value {
                try await client.activate(automation: automationName)
            } else {
                try await client.deactivate(automation: automationName)
            }

            // Reload all automations to get the updated state from the server
            await onDataUpdate()
        } catch {
            assertionFailure()
        }
    }
}

#Preview {
    ContentView()
}

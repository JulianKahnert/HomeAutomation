//
//  AutomationView.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 22.02.25.
//

import SwiftUI

struct AutomationView: View {
    let client: FlowKitClient!
    @State var automation: Automation
    @State var isLoading = false

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
                    Task.detached {
                        await toggleActive(value, automationName: automation.name)
                    }
                }))
                .disabled(isLoading)
                .overlay {
                    ProgressView()
                        .opacity(isLoading ? 1 : 0)
                }
            }

            Section {
                Button("Stop Automation") {
                    Task {
                        do {
                            try await client.stop(automation: automation.name)
                        } catch {
                            print("Failed to stop automation: \(error)")
                        }
                    }
                }
            }
        }
        .navigationTitle(automation.name)
    }

    @concurrent
    func toggleActive(_ value: Bool, automationName: String) async {
        await MainActor.run {
            isLoading = true
        }
        do {
            if value {
                try await client.activate(automation: automationName)
            } else {
                try await client.deactivate(automation: automationName)
            }
            
            await MainActor.run {
                automation.isActive = value
            }
        } catch {
            assertionFailure()
        }

        // swiftlint:disable:next force_try
        try! await Task.sleep(for: .seconds(1))
        await MainActor.run {
            isLoading = false
        }
    }
}

#Preview {
    ContentView()
}

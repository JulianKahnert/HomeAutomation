//
//  AutomationsView.swift
//  ControllerFeatures
//
//  TCA-based automations list view
//

import ComposableArchitecture
import HAModels
import SwiftUI

struct AutomationsView: View {
    let store: StoreOf<AutomationsFeature>

    var body: some View {
        NavigationStack {
            List {
                if !store.runningAutomations.isEmpty {
                    Section("Running") {
                        ForEach(store.runningAutomations, id: \.name) { automation in
                            NavigationLink {
                                AutomationDetailView(
                                    automation: automation,
                                    onActivate: { name in
                                        store.send(.activateAutomation(name))
                                    },
                                    onDeactivate: { name in
                                        store.send(.deactivateAutomation(name))
                                    },
                                    onStop: { name in
                                        store.send(.stopAutomation(name))
                                    }
                                )
                            } label: {
                                automationRow(automation)
                            }
                        }
                    }
                }

                if !store.inactiveAutomations.isEmpty {
                    Section("Inactive") {
                        ForEach(store.inactiveAutomations, id: \.name) { automation in
                            NavigationLink {
                                AutomationDetailView(
                                    automation: automation,
                                    onActivate: { name in
                                        store.send(.activateAutomation(name))
                                    },
                                    onDeactivate: { name in
                                        store.send(.deactivateAutomation(name))
                                    },
                                    onStop: { name in
                                        store.send(.stopAutomation(name))
                                    }
                                )
                            } label: {
                                automationRow(automation)
                            }
                        }
                    }
                }

                if store.automations.isEmpty && !store.isLoading {
                    ContentUnavailableView(
                        "No Automations",
                        systemImage: "lamp.floor",
                        description: Text("Pull to refresh")
                    )
                }
            }
            .navigationTitle("Automations")
            .refreshable {
                store.send(.refresh)
            }
            .onAppear {
                store.send(.onAppear)
            }
            .overlay {
                if store.isLoading && store.automations.isEmpty {
                    ProgressView()
                }
            }
        }
    }

    @ViewBuilder
    private func automationRow(_ automation: AutomationInfo) -> some View {
        HStack {
            Text(automation.name)
                .foregroundStyle(automation.isRunning ? Color.green : Color.primary)
            Spacer()
            if !automation.isActive {
                Image(systemName: "x.circle")
                    .foregroundStyle(Color.red)
            }
        }
    }
}

// MARK: - Automation Detail View

private struct AutomationDetailView: View {
    let automation: AutomationInfo
    let onActivate: (String) -> Void
    let onDeactivate: (String) -> Void
    let onStop: (String) -> Void

    @State private var isLoading = false

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
                Toggle("Is Active", isOn: Binding(
                    get: { automation.isActive },
                    set: { value in
                        toggleActive(value)
                    }
                ))
                .disabled(isLoading)
                .overlay {
                    if isLoading {
                        ProgressView()
                    }
                }
            }

            Section {
                Button("Stop Automation") {
                    onStop(automation.name)
                }
            }
        }
        .navigationTitle(automation.name)
    }

    private func toggleActive(_ value: Bool) {
        Task {
            await MainActor.run {
                isLoading = true
            }

            if value {
                onActivate(automation.name)
            } else {
                onDeactivate(automation.name)
            }

            // Wait for operation to complete
            try? await Task.sleep(for: .seconds(1))

            await MainActor.run {
                isLoading = false
            }
        }
    }
}

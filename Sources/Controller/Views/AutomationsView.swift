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
    @Bindable var store: StoreOf<AutomationsFeature>

    var body: some View {
        NavigationStack {
            List(selection: $store.selectedAutomationIndex) {
                if !store.runningAutomations.isEmpty {
                    Section("Running") {
                        ForEach(store.runningAutomations) { automation in
                            automationRow(automation)
                                .tag(automation.id)
                        }
                    }
                }

                if !store.inactiveAutomations.isEmpty {
                    Section("Inactive") {
                        ForEach(store.inactiveAutomations, id: \.name) { automation in
                            automationRow(automation)
                                .tag(automation.id)
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

//
//  AutomationsFeature.swift
//  ControllerFeatures
//
//  Feature for managing home automations
//

import ComposableArchitecture
import Foundation
import HAModels
import Sharing
import SwiftUI

@Reducer
struct AutomationsFeature: Sendable {

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        @Shared(.automations) var automations: [AutomationInfo] = []
        var isLoading = false
        var selectedAutomationIndex: String?
        var error: String?

        @Presents var selectedAutomation: AutomationDetails.State?

        var runningAutomations: [AutomationInfo] {
            automations.filter(\.isRunning)
        }

        var inactiveAutomations: [AutomationInfo] {
            automations.filter { !$0.isRunning }
        }
    }

    // MARK: - Action

    enum Action: BindableAction, Sendable {
        case binding(BindingAction<State>)
        case onAppear
        case refresh
        case automationsResponse(Result<[AutomationInfo], Error>)
        case automationOperationResponse(Result<Void, Error>)
        case dismissError
        case selectedAutomation(PresentationAction<AutomationDetails.Action>)
    }

    // MARK: - Dependencies

    @Dependency(\.serverClient) var serverClient

    // MARK: - Body

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .onAppear:
                return .run { send in
                    await send(.refresh)
                }

            case .refresh:
                state.isLoading = true
                state.error = nil
                return .run { send in
                    await send(.automationsResponse(
                        Result { try await serverClient.getAutomations() }
                    ))
                }

            case let .automationsResponse(.success(automations)):
                state.isLoading = false
                state.$automations.withLock { $0 = automations }
                return .none

            case let .automationsResponse(.failure(error)):
                state.isLoading = false
                state.error = "Failed to load automations: \(error.localizedDescription)"
                return .none

            case .automationOperationResponse(.success):
                // Refresh the list after a successful operation
                return .run { send in
                    await send(.refresh)
                }

            case let .automationOperationResponse(.failure(error)):
                state.error = "Operation failed: \(error.localizedDescription)"
                return .none

            case .dismissError:
                state.error = nil
                return .none

            case .selectedAutomation:
                return .none
            }
        }
        .ifLet(\.$selectedAutomation, action: \.selectedAutomation) {
            AutomationDetails()
        }
    }
}

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

#Preview {
    AutomationsView(
        store: Store(initialState: AutomationsFeature.State()) {
            AutomationsFeature()
        }
    )
}

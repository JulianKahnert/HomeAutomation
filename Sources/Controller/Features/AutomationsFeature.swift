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

    enum Grouping: String, CaseIterable, Sendable {
        case status
        case type
    }

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        @Shared(.automations) var automations: IdentifiedArrayOf<AutomationInfo> = []
        @Shared(.automationGrouping) var grouping: Grouping = .status
        var isLoading = false
        var selectedAutomationIndex: String?
        var error: String?

        @Presents var selectedAutomation: AutomationDetails.State?

        /// Running automations first within each section.
        var sections: [(title: String, automations: [AutomationInfo])] {
            let sorted = automations.sorted { ($0.isRunning ? 0 : 1, $0.name) < ($1.isRunning ? 0 : 1, $1.name) }
            switch grouping {
            case .status:
                return [("Active", sorted.filter(\.isActive)), ("Inactive", sorted.filter { !$0.isActive })]
                    .filter { !$0.1.isEmpty }
            case .type:
                return Dictionary(grouping: sorted, by: \.typeLabel)
                    .sorted { $0.key < $1.key }
                    .map { ($0.key, $0.value) }
            }
        }
    }

    // MARK: - Action

    enum Action: BindableAction, Sendable {
        case binding(BindingAction<State>)
        case onAppear
        case refresh
        case automationsResponse(Result<[AutomationInfo], Error>)
        case setActive(name: String, Bool)
        case setActiveResponse(name: String, Result<Bool, Error>)
        case dismissError
        case groupingChanged(Grouping)
        case selectedAutomation(PresentationAction<AutomationDetails.Action>)
    }

    // MARK: - Dependencies

    @Dependency(\.serverClient) var serverClient

    // MARK: - Body

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce<State, Action> { state, action in
            switch action {
            case .binding(\.selectedAutomationIndex):
                if let selectedAutomationIndex = state.selectedAutomationIndex,
                   let automation = Shared(state.$automations[id: selectedAutomationIndex]) {
                    state.selectedAutomation = .init(automation: automation)
                } else {
                    state.selectedAutomation = nil
                }
                return .none

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
                let sortedAutomations = automations.sorted { $0.name < $1.name }
                state.$automations.withLock { $0 = IdentifiedArrayOf(uniqueElements: sortedAutomations) }
                return .none

            case let .automationsResponse(.failure(error)):
                state.isLoading = false
                state.error = "Failed to load automations: \(error.localizedDescription)"
                return .none

            case let .setActive(name, isActive):
                state.error = nil
                state.$automations.withLock { $0[id: name]?.isActive = isActive }
                return .run { send in
                    await send(.setActiveResponse(name: name, Result {
                        if isActive {
                            try await serverClient.activate(name)
                        } else {
                            try await serverClient.deactivate(name)
                        }
                        return isActive
                    }))
                }

            case .setActiveResponse(_, .success):
                return .none

            case let .setActiveResponse(name, .failure(error)):
                state.$automations.withLock { $0[id: name]?.isActive.toggle() }
                state.error = "Failed to change \(name): \(error.localizedDescription)"
                return .none

            case .dismissError:
                state.error = nil
                return .none

            case let .groupingChanged(grouping):
                state.$grouping.withLock { $0 = grouping }
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
                Picker("Grouping", selection: Binding(get: { store.grouping }, set: { store.send(.groupingChanged($0)) })) {
                    Text("Active / Inactive").tag(AutomationsFeature.Grouping.status)
                    Text("By Type").tag(AutomationsFeature.Grouping.type)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if let error = store.error {
                    Text(error)
                        .foregroundStyle(.red)
                }

                ForEach(store.sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.automations) { automation in
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
            .navigationDestination(item: $store.scope(\.$selectedAutomation, action: \.selectedAutomation)) { automationStore in
                AutomationDetailView(store: automationStore)
                    .navigationTitle(automationStore.automation.name)
            }
            .sensoryFeedback(.selection, trigger: store.selectedAutomationIndex)
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

    private func automationRow(_ automation: AutomationInfo) -> some View {
        HStack {
            Image(systemName: automation.systemImage)
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(automation.name)
                Text(automation.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            StatusLabel(outcome: .running)
                .opacity(automation.isRunning ? 1 : 0)
            Toggle("Active", isOn: Binding(
                get: { automation.isActive },
                set: { store.send(.setActive(name: automation.name, $0)) }
            ))
            .labelsHidden()
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

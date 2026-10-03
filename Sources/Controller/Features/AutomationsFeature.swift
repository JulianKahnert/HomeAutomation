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
enum AutomationsPath {
    case details(AutomationDetails)
    case entity(EntityHistoryDetailFeature)
    case run(RunDetailFeature)
}

extension AutomationsPath.State: Equatable, Sendable {}
extension AutomationsPath.Action: Sendable {}

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
        var path = StackState<AutomationsPath.State>()
        @Presents var alert: AlertState<Action.Alert>?

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

    enum Action: Sendable {
        case alert(PresentationAction<Alert>)
        case onAppear
        case refresh
        case automationsResponse(Result<[AutomationInfo], Error>)
        case setActive(name: String, Bool)
        case setActiveResponse(name: String, Result<Bool, Error>)
        case groupingChanged(Grouping)
        /// Replaces the stack with the details of the named automation, e.g. from a run in another tab.
        case openAutomation(String)
        case path(StackActionOf<AutomationsPath>)

        enum Alert: Sendable {
            case dismissError
        }
    }

    // MARK: - Dependencies

    @Dependency(\.serverClient) var serverClient

    // MARK: - Body

    var body: some ReducerOf<Self> {
        Reduce<State, Action> { state, action in
            switch action {
            case .alert:
                return .none

            case .onAppear:
                return .run { send in
                    await send(.refresh)
                }

            case .refresh:
                state.isLoading = true
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
                state.alert = Self.errorAlert("Failed to load automations: \(error.localizedDescription)")
                return .none

            case let .setActive(name, isActive):
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
                state.alert = Self.errorAlert("Failed to change \(name): \(error.localizedDescription)")
                return .none

            case let .groupingChanged(grouping):
                state.$grouping.withLock { $0 = grouping }
                return .none

            case let .openAutomation(name):
                guard let automation = Shared(state.$automations[id: name]) else {
                    return .none
                }
                state.path = StackState([.details(AutomationDetails.State(automation: automation))])
                return .none

            case let .path(.element(id, .run(.delegate(.openAutomation)))):
                // A run is only reachable from its automation's details, so going back opens them.
                state.path.pop(from: id)
                return .none

            case .path:
                return .none
            }
        }
        .forEach(\.path, action: \.path)
        .ifLet(\.$alert, action: \.alert)
    }

    private static func errorAlert(_ message: String) -> AlertState<Action.Alert> {
        AlertState {
            TextState("Error")
        } actions: {
            ButtonState(action: .dismissError) {
                TextState("OK")
            }
        } message: {
            TextState(message)
        }
    }
}

struct AutomationsView: View {
    @Bindable var store: StoreOf<AutomationsFeature>

    var body: some View {
        NavigationStack(path: $store.scope(\.path, action: \.path)) {
            List {
                ForEach(store.sections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.automations) { automation in
                            automationRow(automation)
                        }
                    }
                }
            }
            .navigationTitle("Automations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Group By", selection: Binding(get: { store.grouping }, set: { store.send(.groupingChanged($0)) })) {
                            Text("Active / Inactive").tag(AutomationsFeature.Grouping.status)
                            Text("By Type").tag(AutomationsFeature.Grouping.type)
                        }
                    } label: {
                        Label("Group By", systemImage: "rectangle.3.group")
                    }
                }
            }
            .refreshable {
                store.send(.refresh)
            }
            .onAppear {
                store.send(.onAppear)
            }
            .overlay {
                if store.isLoading && store.automations.isEmpty {
                    ProgressView()
                } else if store.automations.isEmpty {
                    ContentUnavailableView(
                        "No Automations",
                        systemImage: "lamp.floor",
                        description: Text("Pull to refresh")
                    )
                }
            }
            .alert($store.scope(\.$alert, action: \.alert))
        } destination: { pathStore in
            switch pathStore.case {
            case let .details(detailsStore):
                AutomationDetailView(store: detailsStore)
                    .navigationTitle(detailsStore.automation.name)
            case let .entity(entityStore):
                EntityHistoryDetailView(store: entityStore)
                    .navigationTitle(entityStore.entity.displayName)
            case let .run(runStore):
                RunDetailView(store: runStore)
            }
        }
    }

    @ViewBuilder
    private func automationRow(_ automation: AutomationInfo) -> some View {
        let toggle = Toggle(isOn: Binding(
            get: { automation.isActive },
            set: { store.send(.setActive(name: automation.name, $0)) }
        )) {
            Label {
                Text(automation.name)
                Group {
                    if automation.isRunning {
                        Text("\(Text("Running").foregroundStyle(.green)) · \(automation.subtitle)")
                    } else {
                        Text(automation.subtitle)
                    }
                }
                .lineLimit(1)
            } icon: {
                Image(systemName: automation.systemImage)
            }
        }
        if let shared = Shared(store.state.$automations[id: automation.id]) {
            NavigationLink(state: AutomationsPath.State.details(AutomationDetails.State(automation: shared))) {
                toggle
            }
        } else {
            toggle
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

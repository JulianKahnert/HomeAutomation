//
//  AutomationDetails.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 19.11.25.
//

import ComposableArchitecture
import Foundation
import HAModels
import Sharing
import SwiftUI

@Reducer
struct AutomationDetails: Sendable {

    @Reducer
    enum Destination {
        case entity(EntityHistoryDetailFeature)
        case run(RunDetailFeature)
    }

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        @Shared var automation: AutomationInfo
        var isLoading = false
        var error: String?
        /// Last 24 hours, newest first.
        var runs: [AutomationRun] = []
        @Presents var destination: Destination.State?
    }

    enum Action: Sendable {
        case destination(PresentationAction<Destination.Action>)
        case entityTapped(EntityId)
        case runTapped(AutomationRun)
        case runsResponse(Result<[AutomationRun], Error>)
        case task
        case stopAutomation
        case updateIsActive(Bool)
        case isActiveOperationResponse(Result<Bool, Error>)
        case stopOperationResponse(Result<Void, Error>)
    }

    @Dependency(\.date.now) var now
    @Dependency(\.serverClient) var serverClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .destination(.presented(.run(.delegate(.openAutomation)))):
                state.destination = nil
                return .none

            case .destination:
                return .none

            case let .entityTapped(entityId):
                state.destination = .entity(EntityHistoryDetailFeature.State(entity: EntityInfo(entityId: entityId)))
                return .none

            case let .runTapped(run):
                state.destination = .run(RunDetailFeature.State(run: run))
                return .none

            case let .runsResponse(.success(runs)):
                state.runs = runs
                return .none

            case let .runsResponse(.failure(error)):
                state.error = "Failed to load runs: \(error.localizedDescription)"
                return .none

            case .task:
                guard state.automation.recordsRuns else { return .none }
                return .run { [name = state.automation.name, now] send in
                    await send(.runsResponse(Result {
                        try await serverClient.getRuns(name, now.addingTimeInterval(-86400), nil, nil)
                    }))
                }
            case .stopAutomation:
                state.error = nil
                state.isLoading = true
                return .run { [name = state.automation.name] send in
                    await send(.stopOperationResponse(
                        Result { try await serverClient.stop(name) }
                    ))
                }

            case .updateIsActive(let isActive):
                state.error = nil
                state.isLoading = true
                return .run { [name = state.automation.name] send in
                    await send(.isActiveOperationResponse(
                        Result {
                            if isActive {
                                try await serverClient.activate(name)
                            } else {
                                try await serverClient.deactivate(name)
                            }
                            return isActive
                        }
                    ))
                }

            case .isActiveOperationResponse(.success(let isActive)):
                state.$automation.withLock { $0.isActive = isActive }
                state.isLoading = false
                return .none

            case let .isActiveOperationResponse(.failure(error)):
                state.isLoading = false
                state.error = "Failed to load automations: \(error.localizedDescription)"
                return .none

            case .stopOperationResponse(.success):
                state.isLoading = false
                state.$automation.withLock { $0.isRunning = false }
                return .send(.task)

            case let .stopOperationResponse(.failure(error)):
                state.isLoading = false
                state.error = "Failed to load automations: \(error.localizedDescription)"
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

extension AutomationDetails.Destination.State: Equatable, Sendable {}
extension AutomationDetails.Destination.Action: Sendable {}

struct AutomationDetailView: View {
    @Bindable var store: StoreOf<AutomationDetails>

    var body: some View {
        Form {
            Section {
                Label(store.automation.typeLabel, systemImage: store.automation.systemImage)
                LabeledContent("Trigger", value: store.automation.triggerDescription)
                Toggle("Active", isOn: Binding(
                    get: { store.automation.isActive },
                    set: { store.send(.updateIsActive($0)) }
                ))
                .disabled(store.isLoading)
                if store.automation.isRunning {
                    Button("Stop", role: .destructive) {
                        store.send(.stopAutomation)
                    }
                    .foregroundStyle(.red)
                    .disabled(store.isLoading)
                }
            } footer: {
                if let error = store.error {
                    Text(error)
                        .foregroundStyle(Color.red)
                }
            }

            if !store.automation.entities.isEmpty {
                Section("Devices") {
                    ForEach(store.automation.entities, id: \.self) { entityId in
                        Button {
                            store.send(.entityTapped(entityId))
                        } label: {
                            LabeledContent(entityId.name, value: entityId.characteristicType.displayName)
                        }
                    }
                }
            }

            Section {
                ForEach(store.runs) { run in
                    Button {
                        store.send(.runTapped(run))
                    } label: {
                        RunRow(run: run, showsAutomationName: false)
                    }
                }
            } header: {
                Text("Runs · 24 h")
            } footer: {
                if !store.automation.recordsRuns {
                    Text("Runs are not recorded for this automation.")
                } else if store.runs.isEmpty {
                    Text("No runs in the last 24 hours.")
                }
            }
        }
        .buttonStyle(.plain)
        .task { await store.send(.task).finish() }
        .navigationDestination(item: $store.scope(state: \.destination?.entity, action: \.destination.entity)) { entityStore in
            EntityHistoryDetailView(store: entityStore)
                .navigationTitle(entityStore.entity.displayName)
        }
        .navigationDestination(item: $store.scope(state: \.destination?.run, action: \.destination.run)) { runStore in
            RunDetailView(store: runStore)
        }
    }
}

#Preview {
    AutomationDetailView(
        store: Store(
            initialState: AutomationDetails.State(
                automation: Shared(value: AutomationInfo(
                    name: "Test Automation",
                    isActive: true,
                    isRunning: true,
                    type: "MotionAtNight"
                ))
            )
        ) {
            AutomationDetails()
        }
    )
}

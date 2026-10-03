//
//  RunDetailFeature.swift
//  Controller
//
//  One automation run with the commands it sent
//

import ComposableArchitecture
import Foundation
import HAModels
import SwiftUI

@Reducer
struct RunDetailFeature: Sendable {

    @ObservableState
    struct State: Equatable, Sendable {
        let run: AutomationRun
        var actions: [ActionLogItem] = []
        var error: String?
    }

    enum Action: Sendable {
        case actionsResponse(Result<[ActionLogItem], Error>)
        case delegate(Delegate)
        case openAutomationButtonTapped
        case task

        enum Delegate: Sendable {
            case openAutomation(String)
        }
    }

    @Dependency(\.serverClient) var serverClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .actionsResponse(.success(actions)):
                state.actions = actions
                return .none

            case let .actionsResponse(.failure(error)):
                state.error = "Failed to load commands: \(error.localizedDescription)"
                return .none

            case .delegate:
                return .none

            case .openAutomationButtonTapped:
                return .send(.delegate(.openAutomation(state.run.automationName)))

            case .task:
                return .run { [runId = state.run.id] send in
                    await send(.actionsResponse(Result { try await serverClient.getActions(nil, runId) }))
                }
            }
        }
    }
}

struct RunDetailView: View {
    let store: StoreOf<RunDetailFeature>

    var body: some View {
        Form {
            Section {
                LabeledContent("Automation", value: store.run.automationName)
                LabeledContent("Trigger", value: store.run.trigger.summary)
                LabeledContent("Start", value: store.run.startedAt.formatted(date: .abbreviated, time: .standard))
                if let endedAt = store.run.endedAt {
                    LabeledContent("Duration", value: Duration.seconds(endedAt.timeIntervalSince(store.run.startedAt))
                        .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated)))
                }
                LabeledContent("Outcome") {
                    StatusLabel(outcome: store.run.outcome)
                }
                if let errorDescription = store.run.errorDescription {
                    LabeledContent("Error") {
                        Text(errorDescription).foregroundStyle(.red)
                    }
                }
            }

            Section {
                ForEach(store.actions) { item in
                    ActionRow(item: item)
                }
            } header: {
                Text("Commands")
            } footer: {
                if let error = store.error {
                    Text(error).foregroundStyle(.red)
                } else if store.actions.isEmpty {
                    Text("No commands recorded. Commands of runs before the last server restart are gone.")
                }
            }

            Section {
                Button("Open Automation") {
                    store.send(.openAutomationButtonTapped)
                }
            }
        }
        .navigationTitle("Run")
        .task { await store.send(.task).finish() }
    }
}

#Preview {
    NavigationStack {
        RunDetailView(
            store: Store(initialState: RunDetailFeature.State(run: AutomationRun(
                automationName: "Bathroom Night Light",
                startedAt: Date().addingTimeInterval(-60),
                endedAt: Date().addingTimeInterval(-46),
                trigger: AutomationTrigger(kind: .entityChange, entityId: nil, summary: "Motion · Eve Motion (Bathroom)"),
                outcome: .failed,
                errorDescription: "Mirror Light (Bathroom) not reachable"
            ))) {
                RunDetailFeature()
            }
        )
    }
}

//
//  RunDetailFeature.swift
//  Controller
//
//  One automation run
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
    }

    enum Action: Sendable {
        case delegate(Delegate)
        case openAutomationButtonTapped

        enum Delegate: Sendable {
            case openAutomation(String)
        }
    }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .delegate:
                return .none

            case .openAutomationButtonTapped:
                return .send(.delegate(.openAutomation(state.run.automationName)))
            }
        }
    }
}

struct RunDetailView<EntityDestination>: View {
    let store: StoreOf<RunDetailFeature>
    /// The stack element showing a device's history; the view sits in more than one stack.
    let entityDestination: (EntityId) -> EntityDestination

    var body: some View {
        Form {
            Section {
                LabeledContent("Automation", value: store.run.automationName)
                if let entityId = store.run.trigger.entityId {
                    NavigationLink(state: entityDestination(entityId)) {
                        LabeledContent("Trigger", value: store.run.trigger.summary)
                    }
                } else {
                    LabeledContent("Trigger", value: store.run.trigger.summary)
                }
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
                Button("Open Automation") {
                    store.send(.openAutomationButtonTapped)
                }
            }
        }
        .navigationTitle("Run")
    }
}

#Preview {
    NavigationStack {
        RunDetailView(
            store: Store(initialState: RunDetailFeature.State(run: AutomationRun(
                automationName: "Bathroom Night Light",
                startedAt: Date().addingTimeInterval(-60),
                endedAt: Date().addingTimeInterval(-46),
                trigger: AutomationTrigger(kind: .entityChange,
                                           entityId: EntityId(placeId: "Bathroom", name: "Eve Motion", characteristicsName: nil, characteristic: .motionSensor),
                                           summary: "Motion · Eve Motion (Bathroom)"),
                outcome: .failed,
                errorDescription: "Mirror Light (Bathroom) not reachable"
            ))) {
                RunDetailFeature()
            }
        ) { $0 }
    }
}

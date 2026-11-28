//
//  ActivityFeedFeature.swift
//  Controller
//
//  Runs of the last 24 hours
//

import ComposableArchitecture
import Foundation
import HAModels
import SwiftUI

@Reducer
struct ActivityFeedFeature: Sendable {

    @ObservableState
    struct State: Equatable, Sendable {
        let runs: [AutomationRun]
    }

    enum Action: Sendable {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}

struct ActivityFeedView: View {
    let store: StoreOf<ActivityFeedFeature>

    var body: some View {
        List {
            ForEach(store.runs) { run in
                NavigationLink(state: OverviewPath.State.run(RunDetailFeature.State(run: run))) {
                    RunRow(run: run)
                }
            }
        }
        .overlay {
            if store.runs.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No Runs", bundle: .module), systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("No automation ran in the last 24 hours.", bundle: .module)
                }
            }
        }
        .navigationTitle(String(localized: "Activity", bundle: .module))
    }
}

#Preview("Empty") {
    NavigationStack {
        ActivityFeedView(store: Store(initialState: ActivityFeedFeature.State(runs: [])) {
            ActivityFeedFeature()
        })
    }
}

#Preview("Runs") {
    let trigger = AutomationTrigger(kind: .sunset, entityId: nil, summary: "Sunset")
    NavigationStack {
        ActivityFeedView(store: Store(initialState: ActivityFeedFeature.State(runs: [
            AutomationRun(
                automationName: "Bathroom Night Light",
                startedAt: Date().addingTimeInterval(-3600),
                endedAt: Date().addingTimeInterval(-3590),
                trigger: trigger,
                outcome: .failed,
                errorDescription: "Mirror Light (Bathroom) not reachable"
            ),
            AutomationRun(
                automationName: "Evening Lights",
                startedAt: Date().addingTimeInterval(-7200),
                endedAt: Date().addingTimeInterval(-7195),
                trigger: trigger,
                outcome: .completed
            )
        ])) {
            ActivityFeedFeature()
        })
    }
}

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
                ContentUnavailableView(
                    "No Runs",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("No automation ran in the last 24 hours.")
                )
            }
        }
        .navigationTitle("Activity")
    }
}

#Preview {
    NavigationStack {
        ActivityFeedView(store: Store(initialState: ActivityFeedFeature.State(runs: [])) {
            ActivityFeedFeature()
        })
    }
}

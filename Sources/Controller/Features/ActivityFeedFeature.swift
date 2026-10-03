//
//  ActivityFeedFeature.swift
//  Controller
//
//  Runs and commands of the last 24 hours in one list
//

import ComposableArchitecture
import Foundation
import HAModels
import SwiftUI

@Reducer
struct ActivityFeedFeature: Sendable {

    enum Filter: String, CaseIterable, Sendable {
        case all = "All"
        case runs = "Runs"
        case commands = "Commands"
    }

    enum Entry: Identifiable, Equatable {
        case run(AutomationRun)
        case command(ActionLogItem)

        var id: UUID {
            switch self {
            case let .run(run): return run.id
            case let .command(item): return item.id
            }
        }

        var date: Date {
            switch self {
            case let .run(run): return run.startedAt
            case let .command(item): return item.timestamp
            }
        }
    }

    @ObservableState
    struct State: Equatable, Sendable {
        let runs: [AutomationRun]
        let actions: [ActionLogItem]
        var filter: Filter = .all

        /// Newest first.
        var entries: [Entry] {
            let runs = filter == .commands ? [] : runs.map(Entry.run)
            let commands = filter == .runs ? [] : actions.map(Entry.command)
            return (runs + commands).sorted { $0.date > $1.date }
        }
    }

    enum Action: BindableAction, Sendable {
        case binding(BindingAction<State>)
        case runTapped(AutomationRun)
    }

    var body: some ReducerOf<Self> {
        BindingReducer()
    }
}

struct ActivityFeedView: View {
    @Bindable var store: StoreOf<ActivityFeedFeature>

    var body: some View {
        List {
            Picker("Filter", selection: $store.filter) {
                ForEach(ActivityFeedFeature.Filter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            Section {
                ForEach(store.entries) { entry in
                    switch entry {
                    case let .run(run):
                        Button {
                            store.send(.runTapped(run))
                        } label: {
                            RunRow(run: run)
                        }
                        .buttonStyle(.plain)
                    case let .command(item):
                        ActionRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("Activity")
    }
}

#Preview {
    NavigationStack {
        ActivityFeedView(store: Store(initialState: ActivityFeedFeature.State(runs: [], actions: [])) {
            ActivityFeedFeature()
        })
    }
}

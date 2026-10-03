//
//  OverviewFeature.swift
//  Controller
//
//  What is happening at home right now
//

import ComposableArchitecture
import Foundation
import HAModels
import Sharing
import SwiftUI

@Reducer
enum OverviewPath {
    case feed(ActivityFeedFeature)
    case run(RunDetailFeature)
}

extension OverviewPath.State: Equatable, Sendable {}
extension OverviewPath.Action: Sendable {}

@Reducer
struct OverviewFeature: Sendable {

    struct Snapshot: Equatable, Sendable {
        var isHealthy: Bool
        var automations: [AutomationInfo]
        var runs: [AutomationRun]
        var actions: [ActionLogItem]
    }

    @ObservableState
    struct State: Equatable, Sendable {
        @Shared(.automations) var automations: IdentifiedArrayOf<AutomationInfo> = []
        var isHealthy: Bool?
        var lastUpdated: Date?
        /// Last 24 hours, newest first.
        var recentRuns: [AutomationRun] = []
        /// Last 24 hours, newest first.
        var recentActions: [ActionLogItem] = []
        var error: String?
        var path = StackState<OverviewPath.State>()

        /// Failed runs, then devices whose commands failed.
        var hints: [String] {
            let runs = recentRuns
                .filter { $0.outcome == .failed }
                .map { "\($0.automationName) failed: \($0.errorDescription ?? "unknown error")" }
            let devices = Dictionary(grouping: recentActions.filter { $0.status == .failed }, by: \.entityId)
                .map { "\($0.key.name) (\($0.key.placeId)): \($0.value.count) failed commands" }
                .sorted()
            return runs + devices
        }
    }

    enum Action: Sendable {
        case delegate(Delegate)
        case path(StackActionOf<OverviewPath>)
        case refresh
        case refreshResponse(Result<Snapshot, Error>)
        case runTapped(AutomationRun)
        case showAllTapped
        case stopButtonTapped(String)
        case task

        enum Delegate: Sendable {
            case openAutomation(String)
        }
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.serverClient) var serverClient

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .delegate:
                return .none

            case let .path(.element(_, .feed(.runTapped(run)))):
                state.path.append(.run(RunDetailFeature.State(run: run)))
                return .none

            case let .path(.element(_, .run(.delegate(.openAutomation(name))))):
                return .send(.delegate(.openAutomation(name)))

            case .path:
                return .none

            case .refresh:
                let since = now.addingTimeInterval(-86400)
                return .run { send in
                    await send(.refreshResponse(Result {
                        async let isHealthy = serverClient.isHealthy()
                        async let automations = serverClient.getAutomations()
                        async let runs = serverClient.getRecentRuns(since, 200)
                        async let actions = serverClient.getActions(1000, nil)
                        return try await Snapshot(
                            isHealthy: isHealthy,
                            automations: automations,
                            runs: runs,
                            actions: actions.filter { $0.timestamp >= since }
                        )
                    }))
                }

            case let .refreshResponse(.success(snapshot)):
                state.error = nil
                state.isHealthy = snapshot.isHealthy
                state.lastUpdated = now
                state.recentRuns = snapshot.runs
                state.recentActions = snapshot.actions
                state.$automations.withLock {
                    $0 = IdentifiedArrayOf(uniqueElements: snapshot.automations.sorted { $0.name < $1.name })
                }
                return .none

            case let .refreshResponse(.failure(error)):
                state.isHealthy = nil
                state.error = "Server unreachable: \(error.localizedDescription)"
                return .none

            case let .runTapped(run):
                state.path.append(.run(RunDetailFeature.State(run: run)))
                return .none

            case .showAllTapped:
                state.path.append(.feed(ActivityFeedFeature.State(runs: state.recentRuns, actions: state.recentActions)))
                return .none

            case let .stopButtonTapped(name):
                return .run { send in
                    try await serverClient.stop(name)
                    await send(.refresh)
                } catch: { error, send in
                    await send(.refreshResponse(.failure(error)))
                }

            case .task:
                // Ends with the view's task, so polling stops when the tab is left.
                return .run { send in
                    await send(.refresh)
                    for await _ in clock.timer(interval: .seconds(30)) {
                        await send(.refresh)
                    }
                }
            }
        }
        .forEach(\.path, action: \.path)
    }
}

struct OverviewView: View {
    @Bindable var store: StoreOf<OverviewFeature>
    let openWindows: [WindowContentState.WindowState]

    var body: some View {
        NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
            List {
                Section {
                    statusRow
                }

                if !openWindows.isEmpty {
                    Section("Open Windows") {
                        ForEach(openWindows, id: \.name) { window in
                            ProgressView(timerInterval: window.opened...window.end, countsDown: false) {
                                LabeledContent(window.name, value: "Limit \(Int(window.maxOpenDuration / 60)) min")
                            } currentValueLabel: {
                                Text("Open for \(Text(window.opened, style: .relative))")
                            }
                            .tint(Date() <= window.end ? Color.accentColor : Color.red)
                        }
                    }
                }

                let running = store.automations.filter(\.isRunning)
                if !running.isEmpty {
                    Section("Running") {
                        ForEach(running) { automation in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(automation.name)
                                    Text(automation.lastRun?.trigger.summary ?? automation.triggerDescription)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button("Stop") {
                                    store.send(.stopButtonTapped(automation.name))
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }

                Section {
                    ForEach(store.recentRuns.prefix(5)) { run in
                        Button {
                            store.send(.runTapped(run))
                        } label: {
                            RunRow(run: run)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    HStack {
                        Text("Recent Runs")
                        Spacer()
                        Button("Show All") {
                            store.send(.showAllTapped)
                        }
                        .font(.footnote)
                    }
                }

                if !store.hints.isEmpty {
                    Section("Notices") {
                        ForEach(store.hints, id: \.self) { hint in
                            Label(hint, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Overview")
            .refreshable { await store.send(.refresh).finish() }
            .task { await store.send(.task).finish() }
        } destination: { pathStore in
            switch pathStore.case {
            case let .feed(feedStore):
                ActivityFeedView(store: feedStore)
            case let .run(runStore):
                RunDetailView(store: runStore)
            }
        }
    }

    private var statusRow: some View {
        HStack {
            Image(systemName: "circle.fill")
                .foregroundStyle(store.isHealthy == true ? Color.green : Color.red)
            if let error = store.error {
                Text(error)
            } else {
                Text(store.isHealthy == false ? "Adapter disconnected" : "Adapter connected")
            }
            Spacer()
            if let lastUpdated = store.lastUpdated {
                Text(lastUpdated, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    OverviewView(
        store: Store(initialState: OverviewFeature.State()) {
            OverviewFeature()
        },
        openWindows: []
    )
}

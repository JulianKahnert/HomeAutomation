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
    case entity(EntityHistoryDetailFeature)
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
        case automationTapped(String)
        case delegate(Delegate)
        case path(StackActionOf<OverviewPath>)
        case refresh
        case refreshResponse(Result<Snapshot, Error>)
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
            case let .automationTapped(name):
                return .send(.delegate(.openAutomation(name)))

            case .delegate:
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
                state.error = error.localizedDescription
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
        NavigationStack(path: $store.scope(\.path, action: \.path)) {
            List {
                Section {
                    statusRow
                } footer: {
                    if let error = store.error {
                        Text(error)
                    }
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
                            Button {
                                store.send(.automationTapped(automation.name))
                            } label: {
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
                                    .tint(.accentColor)
                                    // Reads like a navigation row: it leaves the tab, so it cannot be a NavigationLink.
                                    Image(systemName: "chevron.forward")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            // `.primary` and `.secondary` resolve relative to the button's tint, so the
                            // label stays accent-colored unless the tint itself is the label color.
                            .tint(.primary)
                        }
                    }
                }

                Section("Recent Runs") {
                    ForEach(store.recentRuns.prefix(5)) { run in
                        NavigationLink(state: OverviewPath.State.run(RunDetailFeature.State(run: run))) {
                            RunRow(run: run)
                        }
                    }
                    NavigationLink(
                        "Show All",
                        state: OverviewPath.State.feed(ActivityFeedFeature.State(runs: store.recentRuns, actions: store.recentActions))
                    )
                }

                if !store.hints.isEmpty {
                    Section("Notices") {
                        ForEach(store.hints, id: \.self) { hint in
                            Label {
                                Text(hint)
                            } icon: {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Overview")
            .refreshable { await store.send(.refresh).finish() }
            .task { await store.send(.task).finish() }
        } destination: { pathStore in
            switch pathStore.case {
            case let .entity(entityStore):
                EntityHistoryDetailView(store: entityStore)
                    .navigationTitle(entityStore.entity.displayName)
            case let .feed(feedStore):
                ActivityFeedView(store: feedStore)
            case let .run(runStore):
                RunDetailView(store: runStore) {
                    OverviewPath.State.entity(EntityHistoryDetailFeature.State(entity: EntityInfo(entityId: $0)))
                }
            }
        }
    }

    private var statusRow: some View {
        HStack {
            Image(systemName: "circle.fill")
                .foregroundStyle(store.isHealthy == true ? Color.green : Color.red)
            if store.error != nil {
                Text("Server unreachable")
            } else {
                Text(store.isHealthy == false ? "Adapter disconnected" : "Adapter connected")
            }
            Spacer()
            if let lastUpdated = store.lastUpdated {
                Text("Updated \(Text(lastUpdated, style: .relative)) ago")
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

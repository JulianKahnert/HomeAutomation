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
    }

    @ObservableState
    struct State: Equatable, Sendable {
        @Shared(.automations) var automations: IdentifiedArrayOf<AutomationInfo> = []
        var isHealthy: Bool?
        var lastUpdated: Date?
        /// Last 24 hours, newest first.
        var recentRuns: [AutomationRun] = []
        var error: String?
        var path = StackState<OverviewPath.State>()
    }

    enum Action: Sendable {
        case automationTapped(String)
        case delegate(Delegate)
        case path(StackActionOf<OverviewPath>)
        case refresh
        case refreshResponse(Result<Snapshot, Error>)
        case stopButtonTapped(String)
        case stopResponse(Result<Void, Error>)
        case task

        enum Delegate: Sendable {
            case openAutomation(String)
        }
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.serverClient) var serverClient

    private enum CancelID { case refresh }

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
                return refresh()

            case let .refreshResponse(.success(snapshot)):
                state.error = nil
                state.isHealthy = snapshot.isHealthy
                state.lastUpdated = now
                state.recentRuns = snapshot.runs
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
                    await send(.stopResponse(Result { try await serverClient.stop(name) }))
                }

            case .stopResponse(.success):
                return refresh()

            case let .stopResponse(.failure(error)):
                // The stop failed, not the server: its health stays as it was.
                state.error = error.localizedDescription
                return .none

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

    private func refresh() -> Effect<Action> {
        let since = now.addingTimeInterval(-86400)
        return .run { send in
            await send(.refreshResponse(Result {
                async let isHealthy = serverClient.isHealthy()
                async let automations = serverClient.getAutomations()
                async let runs = serverClient.getRecentRuns(since, 200)
                return try await Snapshot(
                    isHealthy: isHealthy,
                    automations: automations,
                    runs: runs
                )
            }))
        }
        // The timer, pull-to-refresh and the other tabs all refresh: only the newest answer may land.
        .cancellable(id: CancelID.refresh, cancelInFlight: true)
    }
}

struct OverviewView: View {
    @Bindable var store: StoreOf<OverviewFeature>
    let openWindows: [WindowContentState.Window]

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
                        ForEach(openWindows) { window in
                            ProgressView(timerInterval: window.opened...window.closeBy, countsDown: false) {
                                LabeledContent("\(window.name) (\(window.room))",
                                               value: "Limit \(Int(window.closeBy.timeIntervalSince(window.opened) / 60)) min")
                            } currentValueLabel: {
                                Text("Open for \(Text(window.opened, style: .relative))")
                            }
                            .tint(Date() <= window.closeBy ? Color.accentColor : Color.red)
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
                    if store.recentRuns.isEmpty {
                        Text("No runs in the last 24 hours.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.recentRuns.prefix(5)) { run in
                            NavigationLink(state: OverviewPath.State.run(RunDetailFeature.State(run: run))) {
                                RunRow(run: run)
                            }
                        }
                        NavigationLink(
                            "Show All",
                            state: OverviewPath.State.feed(ActivityFeedFeature.State(runs: store.recentRuns))
                        )
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

    private func dot(_ color: Color) -> some View {
        Image(systemName: "circle.fill").foregroundStyle(color)
    }

    private var statusRow: some View {
        HStack {
            switch (store.error, store.isHealthy) {
            case (.some, _):
                dot(.red)
                Text("Server unreachable")
            case (nil, true?):
                dot(.green)
                Text("Adapter connected")
            case (nil, false?):
                dot(.red)
                Text("Adapter disconnected")
            case (nil, nil):
                ProgressView()
                Text("Connecting…")
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

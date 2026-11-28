//
//  AutomationDetails.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 19.11.25.
//

import ComposableArchitecture
import Foundation
import HAModels
import ServerClient
import Sharing
import SwiftUI

@Reducer
struct AutomationDetails: Sendable {

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        @Shared var automation: AutomationInfo
        var isLoading = false
        var error: String?
        /// Last 24 hours, newest first.
        var runs: [AutomationRun] = []
        /// Entity histories of the debug chart, only loaded for `MotionAtNight`.
        var histories: [EntityHistory] = []
        var end = Date()
        @Shared(.serverLocation) var location

        var isMotionAtNight: Bool { automation.type == "MotionAtNight" }
        var start: Date { end.addingTimeInterval(-86400) }
    }

    enum Action: Sendable {
        case automationsResponse(Result<[AutomationInfo], Error>)
        case historiesResponse(Result<[EntityHistory], Error>)
        case locationResponse(Result<Location, Error>)
        case runsResponse(Result<[AutomationRun], Error>)
        case task
        case stopAutomation
        case updateIsActive(Bool)
        case isActiveOperationResponse(requested: Bool, Result<Void, Error>)
        case stopOperationResponse(Result<Void, Error>)
    }

    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.serverClient) var serverClient

    private enum CancelID { case reload }

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .automationsResponse(.success(automations)):
                if let reloaded = automations.first(where: { $0.name == state.automation.name }) {
                    state.$automation.withLock { $0 = reloaded }
                }
                return .none

            case .automationsResponse(.failure):
                // The next visit shows what the server has; nothing to tell the user about a courtesy reload.
                return .none

            case let .historiesResponse(.success(histories)):
                state.histories = histories
                return .none

            case let .locationResponse(.success(location)):
                state.$location.withLock { $0 = location }
                return .none

            case let .historiesResponse(.failure(error)), let .locationResponse(.failure(error)):
                state.error = String(localized: "Failed to load chart data: \(error.localizedDescription)", bundle: .module)
                return .none

            case let .runsResponse(.success(runs)):
                state.runs = runs
                return .none

            case let .runsResponse(.failure(error)):
                state.error = String(localized: "Failed to load runs: \(error.localizedDescription)", bundle: .module)
                return .none

            case .task:
                return load(&state)

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
                        requested: isActive,
                        Result {
                            if isActive {
                                try await serverClient.activate(name)
                            } else {
                                try await serverClient.deactivate(name)
                            }
                        }
                    ))
                }

            case let .isActiveOperationResponse(requested, .success):
                state.$automation.withLock { $0.isActive = requested }
                state.isLoading = false
                return .none

            case let .isActiveOperationResponse(requested, .failure(error)) where error as? ServerClientError == .busy:
                // Queued, not refused: keep what the user asked for.
                state.isLoading = false
                state.$automation.withLock { $0.isActive = requested }
                return reloadLater()

            case let .isActiveOperationResponse(_, .failure(error)):
                state.isLoading = false
                state.error = String(localized: "Failed to change \(state.automation.name): \(error.localizedDescription)", bundle: .module)
                return .none

            case .stopOperationResponse(.success):
                state.isLoading = false
                state.$automation.withLock { $0.isRunning = false }
                return load(&state)

            case let .stopOperationResponse(.failure(error)) where error as? ServerClientError == .busy:
                // Queued, not refused: the reload shows whether the automation has stopped.
                state.isLoading = false
                return reloadLater()

            case let .stopOperationResponse(.failure(error)):
                state.isLoading = false
                state.error = String(localized: "Failed to stop \(state.automation.name): \(error.localizedDescription)", bundle: .module)
                return .none
            }
        }
    }

    /// The runs and, for `MotionAtNight`, the debug chart of the last 24 hours.
    private func load(_ state: inout State) -> Effect<Action> {
        state.end = now
        return .merge(
            state.automation.recordsRuns ? .run { [name = state.automation.name, start = state.start] send in
                await send(.runsResponse(Result {
                    try await serverClient.getRuns(name, start, nil, nil)
                }))
            } : .none,
            state.isMotionAtNight ? loadDebugChart(state) : .none
        )
    }

    /// Asks the server for the automation again after a short delay, e.g. when it queued a change.
    private func reloadLater() -> Effect<Action> {
        .run { send in
            try await clock.sleep(for: .seconds(5))
            await send(.automationsResponse(Result { try await serverClient.getAutomations() }))
        }
        .cancellable(id: CancelID.reload, cancelInFlight: true)
    }

    /// One room-history request per room the automation's devices are in.
    private func loadDebugChart(_ state: State) -> Effect<Action> {
        .run { [entities = state.automation.entities, start = state.start, end = state.end, hasLocation = state.location != nil] send in
            if !hasLocation {
                await send(.locationResponse(Result { try await serverClient.getLocation() }))
            }
            await send(.historiesResponse(Result {
                var histories: [EntityHistory] = []
                for placeId in Set(entities.map(\.placeId)) {
                    histories += try await serverClient.getRoomHistory(placeId, start, end, true)
                }
                return histories.filter { entities.contains($0.entityId) }
            }))
        }
    }
}

struct AutomationDetailView: View {
    @Bindable var store: StoreOf<AutomationDetails>

    var body: some View {
        Form {
            Section {
                LabeledContent(String(localized: "Automation type", bundle: .module), value: store.automation.typeLabel)
                LabeledContent(String(localized: "Trigger", bundle: .module), value: store.automation.triggerDescription)
                Toggle(String(localized: "Active", bundle: .module), isOn: Binding(
                    get: { store.automation.isActive },
                    set: { store.send(.updateIsActive($0)) }
                ))
                .disabled(store.isLoading)
                if store.automation.isRunning {
                    Button(String(localized: "Stop", bundle: .module), role: .destructive) {
                        store.send(.stopAutomation)
                    }
                    .disabled(store.isLoading)
                }
            } footer: {
                if let error = store.error {
                    Text(error)
                        .foregroundStyle(Color.red)
                }
            }

            if !store.automation.entities.isEmpty {
                Section(String(localized: "Devices", bundle: .module)) {
                    ForEach(store.automation.entities, id: \.self) { entityId in
                        NavigationLink(state: AutomationsPath.State.entity(EntityHistoryDetailFeature.State(entity: EntityInfo(entityId: entityId)))) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entityId.name)
                                Text(entityId.kindInRoom)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                ForEach(store.runs) { run in
                    NavigationLink(state: AutomationsPath.State.run(RunDetailFeature.State(run: run))) {
                        RunRow(run: run, showsAutomationName: false)
                    }
                }
            } header: {
                Text("Runs", bundle: .module)
            } footer: {
                if !store.automation.recordsRuns {
                    Text("Runs are not recorded for this automation.", bundle: .module)
                } else if store.runs.isEmpty {
                    Text("No runs in the last 24 hours.", bundle: .module)
                } else {
                    Text("Shows the last 24 hours.", bundle: .module)
                }
            }

            if store.isMotionAtNight {
                motionAtNightSection
            }
        }
        .task { await store.send(.task).finish() }
    }
}

extension AutomationDetailView {
    private var motionAtNightSection: some View {
        let nights = store.location.map {
            StateIntervals.nights(in: DateInterval(start: store.start, end: store.end), latitude: $0.latitude, longitude: $0.longitude)
        } ?? []
        let lanes = store.histories
            .filter { [.switcher, .motionSensor].contains($0.entityId.characteristicType) }
            .map { history in
                TimelineChart.Lane(
                    label: history.entityId.displayName,
                    color: ChartPalette.color(for: history.entityId.characteristicType),
                    intervals: StateIntervals.intervals(items: history.items, isActive: \.stateValue, from: store.start, to: store.end),
                    kind: history.entityId.characteristicType.displayName
                )
            }
        let lux = store.histories
            .filter { $0.entityId.characteristicType == .lightSensor }
            .flatMap(\.items)
            .compactMap { item in item.illuminanceInLux.map { (date: item.timestamp, value: $0) } }
            .sorted { $0.date < $1.date }
        return Section {
            TimelineChart(lanes: lanes, domain: store.start...store.end, nights: nights)
            ValueChart(
                points: lux,
                domain: store.start...store.end,
                color: ChartPalette.color(for: .lightSensor),
                unit: "lx",
                isLogarithmic: true,
                threshold: (MotionAtNightConstants.thresholdInLux, String(localized: "Threshold \(Int(MotionAtNightConstants.thresholdInLux)) lx", bundle: .module)),
                bands: nights
            )
        } header: {
            Text("Trigger Conditions", bundle: .module)
        } footer: {
            Text("Last 24 hours. Grey: sun below the horizon. Motion below the threshold turns the lights on.", bundle: .module)
        }
    }
}

#Preview {
    NavigationStack {
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
}

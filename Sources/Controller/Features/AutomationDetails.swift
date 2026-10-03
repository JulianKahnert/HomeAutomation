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
        case historiesResponse(Result<[EntityHistory], Error>)
        case locationResponse(Result<Location, Error>)
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
            case let .historiesResponse(.success(histories)):
                state.histories = histories
                return .none

            case let .locationResponse(.success(location)):
                state.$location.withLock { $0 = location }
                return .none

            case let .historiesResponse(.failure(error)), let .locationResponse(.failure(error)):
                state.error = "Failed to load chart data: \(error.localizedDescription)"
                return .none

            case let .runsResponse(.success(runs)):
                state.runs = runs
                return .none

            case let .runsResponse(.failure(error)):
                state.error = "Failed to load runs: \(error.localizedDescription)"
                return .none

            case .task:
                state.end = now
                return .merge(
                    state.automation.recordsRuns ? .run { [name = state.automation.name, start = state.start] send in
                        await send(.runsResponse(Result {
                            try await serverClient.getRuns(name, start, nil, nil)
                        }))
                    } : .none,
                    state.isMotionAtNight ? loadDebugChart(state) : .none
                )
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
                LabeledContent("Type", value: store.automation.typeLabel)
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
                        NavigationLink(state: AutomationsPath.State.entity(EntityHistoryDetailFeature.State(entity: EntityInfo(entityId: entityId)))) {
                            LabeledContent(entityId.name, value: entityId.characteristicType.displayName)
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
                Text("Runs")
            } footer: {
                if !store.automation.recordsRuns {
                    Text("Runs are not recorded for this automation.")
                } else if store.runs.isEmpty {
                    Text("No runs in the last 24 hours.")
                } else {
                    Text("Last 24 hours.")
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
                    label: history.entityId.name,
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
                threshold: (MotionAtNightConstants.thresholdInLux, "Threshold \(Int(MotionAtNightConstants.thresholdInLux)) lx"),
                bands: nights
            )
        } header: {
            Text("Trigger Conditions")
        } footer: {
            Text("Last 24 hours. Grey: sun below the horizon. Motion below the threshold turns the lights on.")
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

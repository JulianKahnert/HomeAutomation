//
//  RoomFeature.swift
//  ControllerFeatures
//
//  Timeline of lamps, motion and windows of one room
//

import ComposableArchitecture
import Foundation
import HAModels
import SwiftUI

@Reducer
struct RoomFeature: Sendable {

    enum TimeRange: TimeInterval, CaseIterable, Sendable {
        case hour = 3_600
        case day = 86_400
    }

    @ObservableState
    struct State: Equatable, Sendable {
        let placeId: String
        let entities: [EntityInfo]
        var automations: [AutomationInfo] = []
        var end = Date()
        var error: String?
        var histories: [EntityHistory] = []
        var timeRange: TimeRange = .day
        var weekHistories: [EntityHistory] = []

        var start: Date { end.addingTimeInterval(-timeRange.rawValue) }
    }

    enum Action: BindableAction, Sendable {
        case automationsResponse(Result<[AutomationInfo], Error>)
        case binding(BindingAction<State>)
        case historyResponse(Result<[EntityHistory], Error>)
        case task
        case weekHistoryResponse(Result<[EntityHistory], Error>)
    }

    @Dependency(\.date.now) var now
    @Dependency(\.serverClient) var serverClient

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case let .automationsResponse(.success(automations)):
                state.automations = automations.filter { $0.entities.contains { $0.placeId == state.placeId } }
                return .none

            case let .historyResponse(.success(histories)):
                state.histories = histories
                return .none

            case let .weekHistoryResponse(.success(histories)):
                state.weekHistories = histories
                return .none

            case let .automationsResponse(.failure(error)), let .historyResponse(.failure(error)), let .weekHistoryResponse(.failure(error)):
                state.error = error.localizedDescription
                return .none

            case .binding(\.timeRange):
                return loadHistory(&state)

            case .binding:
                return .none

            case .task:
                return .merge(
                    loadHistory(&state),
                    .run { send in
                        await send(.automationsResponse(Result { try await serverClient.getAutomations() }))
                    },
                    .run { [placeId = state.placeId, end = state.end] send in
                        await send(.weekHistoryResponse(Result {
                            try await serverClient.getRoomHistory(placeId, end.addingTimeInterval(-7 * 86_400), end, true)
                        }))
                    }
                )
            }
        }
    }

    private func loadHistory(_ state: inout State) -> Effect<Action> {
        state.end = now
        state.error = nil
        return .run { [placeId = state.placeId, start = state.start, end = state.end] send in
            await send(.historyResponse(Result {
                try await serverClient.getRoomHistory(placeId, start, end, true)
            }))
        }
    }
}

struct RoomView: View {
    @Bindable var store: StoreOf<RoomFeature>

    private static let laneTypes: [CharacteristicsType] = [.switcher, .motionSensor, .contactSensor]

    private var lanes: [TimelineChart.Lane] {
        store.histories
            .filter { Self.laneTypes.contains($0.entityId.characteristicType) }
            .sorted { ($0.entityId.characteristicType.rawValue, $0.entityId.name) < ($1.entityId.characteristicType.rawValue, $1.entityId.name) }
            .map { history in
                TimelineChart.Lane(
                    label: history.entityId.name,
                    color: ChartPalette.color(for: history.entityId.characteristicType),
                    intervals: StateIntervals.intervals(items: history.items, isActive: \.stateValue, from: store.start, to: store.end),
                    kind: history.entityId.characteristicType.displayName
                )
            }
    }

    private var weekStart: Date { store.end.addingTimeInterval(-7 * 86_400) }

    private func windowIntervals(_ histories: [EntityHistory], from start: Date, to end: Date) -> [DateInterval] {
        histories
            .filter { $0.entityId.characteristicType == .contactSensor }
            .flatMap { StateIntervals.intervals(items: $0.items, isActive: \.isContactOpen, from: start, to: end) }
    }

    var body: some View {
        List {
            Section {
                Picker("Time Range", selection: $store.timeRange) {
                    Text("Last Hour").tag(RoomFeature.TimeRange.hour)
                    Text("24 Hours").tag(RoomFeature.TimeRange.day)
                }
                .pickerStyle(.segmented)
                if lanes.isEmpty {
                    Text(store.error ?? "No lamps, motion sensors or windows with history.")
                        .foregroundStyle(.secondary)
                } else {
                    TimelineChart(lanes: lanes, domain: store.start...store.end)
                }
            } header: {
                Text("Timeline")
            }

            if let co2 = store.histories.first(where: { $0.entityId.characteristicType == .carbonDioxideSensorId }) {
                Section("CO₂") {
                    ValueChart(
                        points: co2.items.compactMap { item in item.carbonDioxideSensorId.map { (item.timestamp, Double($0)) } },
                        domain: store.start...store.end,
                        color: ChartPalette.color(for: .carbonDioxideSensorId),
                        unit: "ppm",
                        threshold: (1_000, "1000 ppm"),
                        bands: windowIntervals(store.histories, from: store.start, to: store.end),
                        bandColor: ChartPalette.color(for: .contactSensor).opacity(0.2)
                    )
                }
            }

            if store.weekHistories.contains(where: { $0.entityId.characteristicType == .contactSensor }) {
                Section("Ventilation per Day") {
                    DailyBarChart(
                        bars: DailyTotals.dailyTotals(windowIntervals(store.weekHistories, from: weekStart, to: store.end), days: DailyTotals.days(count: 7, endingAt: store.end, calendar: .current), calendar: .current)
                            .map { ($0.day, $0.duration / 60) },
                        color: ChartPalette.color(for: .contactSensor),
                        unit: "min"
                    )
                }
            }

            Section("Devices") {
                ForEach(store.entities) { entity in
                    NavigationLink(state: RoomsPath.State.entity(EntityHistoryDetailFeature.State(entity: entity))) {
                        Label {
                            Text(entity.entityId.name)
                            Text(entity.formattedCharacteristicDisplayName)
                        } icon: {
                            Image(systemName: entity.entityId.characteristicType.systemImage)
                        }
                    }
                }
            }

            if !store.automations.isEmpty {
                Section("Automations") {
                    ForEach(store.automations) { automation in
                        Label(automation.name, systemImage: automation.systemImage)
                    }
                }
            }
        }
        .navigationTitle(store.placeId)
        .task { await store.send(.task).finish() }
    }
}

#Preview {
    NavigationStack {
        RoomView(
            store: Store(initialState: RoomFeature.State(placeId: "Kitchen", entities: [])) {
                RoomFeature()
            }
        )
    }
}

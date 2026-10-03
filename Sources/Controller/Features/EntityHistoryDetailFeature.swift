//
//  EntityHistoryDetailFeature.swift
//  ControllerFeatures
//
//  Feature for displaying entity history charts and details
//

import Charts
import ComposableArchitecture
import Foundation
import HAModels
import SwiftUI

@Reducer
struct EntityHistoryDetailFeature: Sendable {

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        let entity: EntityInfo
        var historyItems: [EntityHistoryItem] = []
        var isLoading = false
        var timeRange: TimeRange = .hour
        var nextCursor: Date?
        @Presents var alert: AlertState<Action.Alert>?

        var chartData: [EntityHistoryItem] {
            historyItems
        }

        var dateRange: (start: Date, end: Date) {
            let now = Date()
            let start: Date
            switch timeRange {
            case .hour:
                start = now.addingTimeInterval(-3600)
            case .day:
                start = now.addingTimeInterval(-86400)
            case .week:
                start = now.addingTimeInterval(-604800)
            }
            return (start, now)
        }
    }

    enum TimeRange: String, CaseIterable, Sendable {
        case hour = "1h"
        case day = "24h"
        case week = "7d"

        var displayName: String {
            switch self {
            case .hour: return "Last Hour"
            case .day: return "Last 24 Hours"
            case .week: return "Last 7 Days"
            }
        }
    }

    // MARK: - Action

    enum Action: Sendable, BindableAction {
        case onAppear
        case refresh
        case loadNextPage
        case historyResponse(Result<EntityHistoryResponse, Error>)
        case timeRangeChanged(TimeRange)
        case binding(BindingAction<State>)
        case alert(PresentationAction<Alert>)

        enum Alert: Sendable {
            case dismissError
        }
    }

    // MARK: - Dependencies

    @Dependency(\.serverClient) var serverClient

    // MARK: - Body

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .run { send in
                    await send(.refresh)
                }

            case .refresh:
                state.isLoading = true
                state.alert = nil
                state.historyItems = []
                state.nextCursor = nil

                let entityId = state.entity.entityId
                let dateRange = state.dateRange

                return .run { send in
                    await send(.historyResponse(
                        Result {
                            try await serverClient.getEntityHistory(
                                entityId,
                                dateRange.start,
                                dateRange.end,
                                nil,
                                1000,
                                true
                            )
                        }
                    ))
                }

            case .loadNextPage:
                guard let cursor = state.nextCursor else {
                    return .none
                }

                let entityId = state.entity.entityId
                let dateRange = state.dateRange

                return .run { send in
                    await send(.historyResponse(
                        Result {
                            try await serverClient.getEntityHistory(
                                entityId,
                                dateRange.start,
                                dateRange.end,
                                cursor,
                                1000,
                                false
                            )
                        }
                    ))
                }

            case let .historyResponse(.success(response)):
                state.isLoading = false

                // Append new items and remove duplicates
                let newItems = response.items.filter { newItem in
                    !state.historyItems.contains(where: { $0.id == newItem.id })
                }
                state.historyItems.append(contentsOf: newItems)
                state.historyItems.sort { $0.timestamp > $1.timestamp }

                state.nextCursor = response.nextCursor

                // Automatically load next page if there's more data
                if response.nextCursor != nil {
                    return .run { send in
                        await send(.loadNextPage)
                    }
                }
                return .none

            case let .historyResponse(.failure(error)):
                state.isLoading = false
                state.alert = AlertState {
                    TextState("Error")
                } actions: {
                    ButtonState(action: .dismissError) {
                        TextState("OK")
                    }
                } message: {
                    TextState("Failed to load history: \(error.localizedDescription)")
                }
                return .none

            case let .timeRangeChanged(newRange):
                state.timeRange = newRange
                return .run { send in
                    await send(.refresh)
                }

            case .binding:
                return .none

            case .alert:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }
}

struct EntityHistoryDetailView: View {
    @Bindable var store: StoreOf<EntityHistoryDetailFeature>

    var body: some View {
        List {
            Section {
                Picker("Time Range", selection: $store.timeRange) {
                    ForEach(EntityHistoryDetailFeature.TimeRange.allCases, id: \.self) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: store.timeRange) { _, newValue in
                    store.send(.timeRangeChanged(newValue))
                }

                if !store.chartData.isEmpty {
                    chartView
                } else if store.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("No history data available for this time range")
                    )
                }
            }

            if store.timeRange == .week {
                Section("Per Day") {
                    dailyChart
                }
            }

            if !store.historyItems.isEmpty {
                Section("History") {
                    ForEach(store.historyItems) { item in
                        historyRow(item)
                    }
                }
            }
        }
        .refreshable {
            store.send(.refresh)
        }
        .onAppear {
            store.send(.onAppear)
        }
        .alert($store.scope(\.$alert, action: \.alert))
    }

    private var laneLabel: String {
        switch store.entity.entityId.characteristicType {
        case .contactSensor: "Open"
        case .motionSensor: "Motion"
        default: "On"
        }
    }

    @ViewBuilder
    private var chartView: some View {
        let dateRange = store.state.dateRange
        let range = dateRange.start...dateRange.end
        let isBoolean = store.chartData.contains { $0.stateValue != nil }
        let isLux = store.entity.entityId.characteristicType == .lightSensor

        if isBoolean {
            TimelineChart(
                lanes: [.init(
                    label: laneLabel,
                    color: ChartPalette.color(for: store.entity.entityId.characteristicType),
                    intervals: StateIntervals.intervals(items: store.chartData, isActive: \.stateValue, from: dateRange.start, to: dateRange.end)
                )],
                domain: range
            )
        } else {
            ValueChart(
                points: store.chartData.compactMap { item in item.primaryValue.map { (item.timestamp, $0) } },
                domain: range,
                color: ChartPalette.color(for: store.entity.entityId.characteristicType),
                unit: store.entity.entityId.characteristicType == .lightSensor ? "lx" : "",
                isLogarithmic: isLux,
                height: 240
            )
        }
    }

    /// Per-day summaries of the 7-day range: on-duration for lamps, max and time-weighted mean for lux and CO₂.
    @ViewBuilder
    private var dailyChart: some View {
        let dateRange = store.state.dateRange
        let type = store.entity.entityId.characteristicType
        let days = DailyTotals.days(count: 7, endingAt: dateRange.end, calendar: .current)
        if type == .switcher {
            let intervals = StateIntervals.intervals(items: store.chartData, isActive: \.isDeviceOn, from: dateRange.start, to: dateRange.end)
            DailyBarChart(
                bars: DailyTotals.dailyTotals(intervals, days: days, calendar: .current).map { ($0.day, $0.duration / 3_600) },
                color: ChartPalette.color(for: type),
                unit: "h"
            )
        } else if type == .lightSensor || type == .carbonDioxideSensorId {
            let samples = store.chartData.compactMap { item in item.primaryValue.map { (date: item.timestamp, value: $0) } }
            let stats = DailyTotals.dailyStats(samples, days: days, end: dateRange.end, calendar: .current)
            DailyBarChart(
                bars: stats.map { ($0.day, $0.max) },
                color: ChartPalette.color(for: type).opacity(0.6),
                unit: type == .lightSensor ? "lx" : "ppm",
                points: stats.map { ($0.day, $0.mean) },
                barLabel: "Daily Max"
            )
        }
    }

    @ViewBuilder
    private func historyRow(_ item: EntityHistoryItem) -> some View {
        HStack {
            // Color indicator (if color data available)
            if let color = item.color {
                Circle()
                    .fill(color)
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(item.valueDescription)
        }
    }
}

#if DEBUG
#Preview {
    EntityHistoryDetailView(
        store: Store(
            initialState: EntityHistoryDetailFeature.State(
                entity: .preview()
            )
        ) {
            EntityHistoryDetailFeature()
        }
    )
}
#endif

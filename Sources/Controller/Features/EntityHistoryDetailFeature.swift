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
        /// A reload keeps the shown items until its first page arrives, which replaces them.
        var replacesHistory = false
        var timeRange: TimeRange = .hour
        @Presents var alert: AlertState<Action.Alert>?

        /// When the shown range ended: the moment of the last refresh.
        var rangeEnd: Date?

        /// Whether any point of the history can be drawn: a state for the timeline, a number for the value chart.
        /// A text value (a window deadline) has history but nothing to plot.
        var canPlot: Bool {
            historyItems.contains { $0.primaryValue != nil }
        }

        var isBoolean: Bool {
            historyItems.contains { $0.stateValue != nil }
        }

        var dateRange: (start: Date, end: Date) {
            let now = rangeEnd ?? Date()
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
            case .hour: return String(localized: "Last Hour", bundle: .module)
            case .day: return String(localized: "Last 24 Hours", bundle: .module)
            case .week: return String(localized: "Last 7 Days", bundle: .module)
            }
        }
    }

    // MARK: - Action

    enum Action: Sendable, BindableAction {
        case onAppear
        case refresh
        case historyResponse(Result<EntityHistoryResponse, Error>)
        case binding(BindingAction<State>)
        case alert(PresentationAction<Alert>)

        enum Alert: Sendable {
            case dismissError
        }
    }

    // MARK: - Dependencies

    @Dependency(\.date.now) var now
    @Dependency(\.serverClient) var serverClient

    private enum CancelID { case history }

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
                return refresh(&state, clearing: false)

            case let .historyResponse(.success(response)):
                state.isLoading = false

                // The server's cursor is exclusive, so a page never repeats an item of the pages before.
                if state.replacesHistory {
                    state.historyItems = response.items
                    state.replacesHistory = false
                } else {
                    state.historyItems.append(contentsOf: response.items)
                }
                state.historyItems.sort { $0.timestamp > $1.timestamp }
                return .none

            case let .historyResponse(.failure(error)):
                state.isLoading = false
                state.alert = AlertState {
                    TextState(String(localized: "Error", bundle: .module))
                } actions: {
                    ButtonState(action: .dismissError) {
                        TextState(String(localized: "OK", bundle: .module))
                    }
                } message: {
                    TextState(String(localized: "Failed to load history: \(error.localizedDescription)", bundle: .module))
                }
                return .none

            case .binding(\.timeRange):
                return refresh(&state, clearing: true)

            case .binding:
                return .none

            case .alert:
                return .none
            }
        }
        .ifLet(\.$alert, action: \.alert)
    }

    /// `clearing` empties the list at once (a new range); otherwise the old items stay until the first page.
    private func refresh(_ state: inout State, clearing: Bool) -> Effect<Action> {
        state.isLoading = true
        state.rangeEnd = now
        state.alert = nil
        if clearing {
            state.historyItems = []
        }
        state.replacesHistory = !clearing

        let entityId = state.entity.entityId
        let dateRange = state.dateRange

        // All pages in one effect: it is cancelled as a whole when the screen is popped or
        // the range changes, so no late page reaches a removed element or a new range.
        return .run { send in
            var cursor: Date?
            repeat {
                let response = try await serverClient.getEntityHistory(
                    entityId,
                    dateRange.start,
                    dateRange.end,
                    cursor,
                    1000,
                    cursor == nil
                )
                await send(.historyResponse(.success(response)))
                cursor = response.nextCursor
            } while cursor != nil
        } catch: { error, send in
            await send(.historyResponse(.failure(error)))
        }
        .cancellable(id: CancelID.history, cancelInFlight: true)
    }
}

struct EntityHistoryDetailView: View {
    @Bindable var store: StoreOf<EntityHistoryDetailFeature>

    var body: some View {
        List {
            Section {
                Picker(String(localized: "Time Range", bundle: .module), selection: $store.timeRange) {
                    ForEach(EntityHistoryDetailFeature.TimeRange.allCases, id: \.self) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                if store.canPlot {
                    chartView
                } else if store.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else if store.historyItems.isEmpty {
                    Text("No history in this time range.", bundle: .module)
                        .foregroundStyle(.secondary)
                } else {
                    // A text value (a window deadline) has history but nothing to plot.
                    Text("This value has no chart.", bundle: .module)
                        .foregroundStyle(.secondary)
                }
            }

            if store.timeRange == .week {
                Section(String(localized: "Per Day", bundle: .module)) {
                    dailyChart
                }
            }

            if !store.historyItems.isEmpty {
                Section(String(localized: "History", bundle: .module)) {
                    ForEach(store.historyItems) { item in
                        historyRow(item)
                    }
                }
            }
        }
        .refreshable {
            await store.send(.refresh).finish()
        }
        .task { await store.send(.onAppear).finish() }
        .alert($store.scope(\.$alert, action: \.alert))
    }

    private var laneLabel: String {
        switch store.entity.entityId.characteristicType {
        case .contactSensor: String(localized: "Open", bundle: .module)
        case .motionSensor: String(localized: "Motion", bundle: .module)
        default: String(localized: "Switched on", bundle: .module)
        }
    }

    @ViewBuilder
    private var chartView: some View {
        let dateRange = store.state.dateRange
        let range = dateRange.start...dateRange.end
        let isBoolean = store.isBoolean
        let isLux = store.entity.entityId.characteristicType == .lightSensor

        if isBoolean {
            TimelineChart(
                lanes: [.init(
                    label: laneLabel,
                    color: ChartPalette.color(for: store.entity.entityId.characteristicType),
                    intervals: StateIntervals.intervals(items: store.historyItems, isActive: \.stateValue, from: dateRange.start, to: dateRange.end)
                )],
                domain: range
            )
        } else {
            ValueChart(
                points: store.historyItems.compactMap { item in item.primaryValue.map { (item.timestamp, $0) } },
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
            let intervals = StateIntervals.intervals(items: store.historyItems, isActive: \.isDeviceOn, from: dateRange.start, to: dateRange.end)
            DailyBarChart(
                bars: DailyTotals.dailyTotals(intervals, days: days, calendar: .current).map { ($0.day, $0.duration / 3_600) },
                color: ChartPalette.color(for: type),
                unit: "h"
            )
        } else if type == .lightSensor || type == .carbonDioxideSensorId {
            let samples = store.historyItems.compactMap { item in item.primaryValue.map { (date: item.timestamp, value: $0) } }
            let stats = DailyTotals.dailyStats(samples, days: days, end: dateRange.end, calendar: .current)
            DailyBarChart(
                bars: stats.map { ($0.day, $0.max) },
                color: ChartPalette.color(for: type).opacity(0.6),
                unit: type == .lightSensor ? "lx" : "ppm",
                points: stats.map { ($0.day, $0.mean) },
                barLabel: String(localized: "Daily Max", bundle: .module)
            )
        }
    }

    private func historyRow(_ item: EntityHistoryItem) -> some View {
        LabeledContent {
            Text(item.timestamp, format: .dateTime.day().month().hour().minute())
        } label: {
            HStack {
                if let color = item.color {
                    Circle()
                        .fill(color)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                }
                Text(item.valueDescription)
            }
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

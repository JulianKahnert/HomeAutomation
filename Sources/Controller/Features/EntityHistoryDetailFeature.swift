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
                                5000  // Higher limit for initial load
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
                                1000
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
        ScrollView {
            VStack(spacing: 16) {
                // Time range picker
                Picker("Time Range", selection: $store.timeRange) {
                    ForEach(EntityHistoryDetailFeature.TimeRange.allCases, id: \.self) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .onChange(of: store.timeRange) { _, newValue in
                    store.send(.timeRangeChanged(newValue))
                }

                // Chart
                if !store.chartData.isEmpty {
                    chartView
                        .frame(height: 300)
                        .padding(.horizontal)
                } else if store.isLoading {
                    ProgressView()
                        .frame(height: 300)
                } else {
                    ContentUnavailableView(
                        "No Data",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("No history data available for this time range")
                    )
                    .frame(height: 300)
                }

                // History list
                if !store.historyItems.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(store.historyItems) { item in
                            historyRow(item)
                            Divider()
                        }
                    }
                    .background(.secondary.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .refreshable {
            store.send(.refresh)
        }
        .onAppear {
            store.send(.onAppear)
        }
        .alert(store: store.scope(state: \.$alert, action: \.alert))
    }

    @ViewBuilder
    private var chartView: some View {
        let dateRange = store.state.dateRange

        Chart {
            ForEach(store.chartData) { item in
                if let value = item.primaryValue {
                    LineMark(
                        x: .value("Time", item.timestamp),
                        y: .value("Value", value)
                    )
                    .foregroundStyle(.blue)

                    PointMark(
                        x: .value("Time", item.timestamp),
                        y: .value("Value", value)
                    )
                    .foregroundStyle(.blue)
                }
            }
        }
        .chartXScale(domain: dateRange.start...dateRange.end)
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
    }

    @ViewBuilder
    private func historyRow(_ item: EntityHistoryItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text(item.valueDescription)
                .font(.body)
                .bold()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
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

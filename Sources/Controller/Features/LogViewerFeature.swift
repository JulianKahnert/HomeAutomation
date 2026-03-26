//
//  LogViewerFeature.swift
//  ControllerFeatures
//
//  TCA wrapper that loads log entries and presents LogViewerView
//

import ComposableArchitecture
import Foundation
import Shared
import SwiftUI

@Reducer
struct LogViewerFeature: Sendable {

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        var logEntries: [LogEntry] = []
        var isLoading = false
    }

    // MARK: - Action

    enum Action: Sendable {
        case onAppear
        case refresh
        case logEntriesLoaded([LogEntry])
    }

    // MARK: - Body

    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.refresh)

            case .refresh:
                state.isLoading = true
                return .run { send in
                    // 24 hours
                    let since = Date().addingTimeInterval(-86400)
                    let entries = LogReader.readEntries(since: since, basePath: .documentsDirectory)
                    await send(.logEntriesLoaded(entries))
                }

            case let .logEntriesLoaded(entries):
                state.logEntries = entries
                state.isLoading = false
                return .none
            }
        }
    }
}

// MARK: - Feature View (TCA → portable LogViewerView)

struct LogViewerFeatureView: View {
    let store: StoreOf<LogViewerFeature>

    var body: some View {
        LogViewerView(
            entries: store.logEntries,
            isLoading: store.isLoading,
            onRefresh: { store.send(.refresh) }
        )
        .onAppear {
            store.send(.onAppear)
        }
    }
}

#Preview {
    NavigationStack {
        LogViewerFeatureView(
            store: Store(initialState: LogViewerFeature.State()) {
                LogViewerFeature()
            }
        )
    }
}

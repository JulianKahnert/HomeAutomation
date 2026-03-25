//
//  LogViewerFeature.swift
//  ControllerFeatures
//
//  In-app log viewer for debugging Live Activity token lifecycle
//

import ComposableArchitecture
import Foundation
import SwiftUI

@Reducer
struct LogViewerFeature: Sendable {

    // MARK: - State

    @ObservableState
    struct State: Equatable, Sendable {
        var logEntries: [LogEntry] = []
        var searchText: String = ""
        var isLoading = false

        var filteredEntries: [LogEntry] {
            guard !searchText.isEmpty else { return logEntries }
            let search = searchText.localizedLowercase
            return logEntries.filter {
                $0.message.localizedLowercase.contains(search)
                || $0.label.localizedLowercase.contains(search)
                || $0.level.localizedLowercase.contains(search)
            }
        }

        var exportAsText: String {
            filteredEntries.reversed().map(\.rawLine).joined(separator: "\n")
        }
    }

    // MARK: - Action

    enum Action: Sendable, BindableAction {
        case onAppear
        case refresh
        case logEntriesLoaded([LogEntry])
        case binding(BindingAction<State>)
    }

    // MARK: - Dependencies

    @Dependency(\.logFile) var logFile

    // MARK: - Body

    var body: some ReducerOf<Self> {
        BindingReducer()
        Reduce { state, action in
            switch action {
            case .onAppear:
                return .send(.refresh)

            case .refresh:
                state.isLoading = true
                return .run { send in
                    let since = Date().addingTimeInterval(-86400)
                    let entries = await logFile.readLogEntries(since)
                    await send(.logEntriesLoaded(entries))
                }

            case let .logEntriesLoaded(entries):
                state.logEntries = entries
                state.isLoading = false
                return .none

            case .binding:
                return .none
            }
        }
    }
}

// MARK: - View

struct LogViewerView: View {
    @Bindable var store: StoreOf<LogViewerFeature>

    var body: some View {
        List {
            ForEach(store.filteredEntries) { entry in
                logRow(entry)
            }
        }
        .searchable(text: $store.searchText, prompt: "Filter logs...")
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.send(.refresh)
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(store.isLoading)
            }

            ToolbarItem(placement: .secondaryAction) {
                ShareLink(
                    item: store.exportAsText,
                    preview: SharePreview(
                        "Logs_\(Date().ISO8601Format()).txt",
                        image: Image(systemName: "doc.text")
                    )
                )
                .disabled(store.logEntries.isEmpty)
            }
        }
        .refreshable {
            store.send(.refresh)
        }
        .onAppear {
            store.send(.onAppear)
        }
        .overlay {
            if store.isLoading && store.logEntries.isEmpty {
                ProgressView()
            } else if store.logEntries.isEmpty && !store.isLoading {
                ContentUnavailableView(
                    "No Log Entries",
                    systemImage: "doc.text",
                    description: Text("Logs from the last 24 hours will appear here")
                )
            }
        }
    }

    @ViewBuilder
    private func logRow(_ entry: LogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.level.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(levelColor(entry.level).opacity(0.2))
                    .foregroundStyle(levelColor(entry.level))
                    .clipShape(Capsule())

                Text(entry.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.message)
                .font(.caption)
                .lineLimit(3)
        }
    }

    private func levelColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "debug", "trace": .gray
        case "info", "notice": .blue
        case "warning": .orange
        case "error": .orange
        case "critical": .red
        default: .secondary
        }
    }
}

#Preview {
    NavigationStack {
        LogViewerView(
            store: Store(initialState: LogViewerFeature.State()) {
                LogViewerFeature()
            }
        )
    }
}

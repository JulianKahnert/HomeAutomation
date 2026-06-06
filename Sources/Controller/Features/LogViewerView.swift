//
//  LogViewerView.swift
//

import Foundation
import Shared
import SwiftUI

/// Displays a searchable, exportable list of ``LogEntry`` items.
///
/// The view receives all entries from outside and handles filtering,
/// display, and export internally. Integrate with any state management
/// (TCA, @Observable, @State) by passing entries and a refresh callback.
struct LogViewerView: View {
    let entries: [LogEntry]
    let isLoading: Bool
    var onRefresh: () -> Void

    @State private var searchText = ""

    private var filteredEntries: [LogEntry] {
        guard !searchText.isEmpty else { return entries }
        let search = searchText.localizedLowercase
        return entries.filter {
            $0.message.localizedLowercase.contains(search)
            || $0.label.localizedLowercase.contains(search)
            || $0.level.localizedLowercase.contains(search)
        }
    }

    private var exportAsText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return filteredEntries.reversed().map { entry in
            "[\(formatter.string(from: entry.timestamp))] \(entry.level) \(entry.label): \(entry.message)"
        }.joined(separator: "\n")
    }

    var body: some View {
        List {
            ForEach(filteredEntries) { entry in
                logRow(entry)
            }
        }
        .searchable(text: $searchText, prompt: "Filter logs...")
        .navigationTitle("Logs")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: exportAsText,
                    preview: SharePreview(
                        "Logs_\(Date().ISO8601Format()).txt",
                        image: Image(systemName: "doc.text")
                    )
                )
                .disabled(entries.isEmpty)
            }

            ToolbarItem(placement: .secondaryAction) {
                Button {
                    onRefresh()
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .refreshable {
            onRefresh()
        }
        .overlay {
            if isLoading && entries.isEmpty {
                ProgressView()
            } else if entries.isEmpty && !isLoading {
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
        let isCritical = entry.level.lowercased() == "critical"

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.level.uppercased())
                    .font(isCritical ? .caption.bold() : .caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(levelColor(entry.level).opacity(isCritical ? 0.4 : 0.2))
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
                .lineLimit(isCritical ? 10 : 3)
        }
        .listRowBackground(isCritical ? Color.red.opacity(0.08) : nil)
    }

    private func levelColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "debug", "trace": .gray
        case "info", "notice": .blue
        case "warning": .yellow
        case "error": .orange
        case "critical": .red
        default: .secondary
        }
    }
}

#Preview {
    NavigationStack {
        LogViewerView(
            entries: [
                LogEntry(timestamp: Date(), level: "critical", label: "HomeManager", message: "Failed to persist entity item Error(connectionReset)"),
                LogEntry(timestamp: Date().addingTimeInterval(-5), level: "info", label: "AppFeature", message: "Scene phase: inactive -> active"),
                LogEntry(timestamp: Date().addingTimeInterval(-10), level: "error", label: "AppFeature", message: "Failed to register push token"),
                LogEntry(timestamp: Date().addingTimeInterval(-60), level: "debug", label: "LiveActivity", message: "hasActiveActivities: 1 active"),
            ],
            isLoading: false,
            onRefresh: {}
        )
    }
}

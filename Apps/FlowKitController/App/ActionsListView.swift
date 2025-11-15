//
//  ActionsListView.swift
//  FlowKit Controller
//
//  Created by Julian Kahnert on 15.11.25.
//

import HAModels
import SwiftUI

struct ActionsListView: View {
    let client: FlowKitClient

    @State private var actions: [ActionLogItem] = []
    @State private var searchText = ""
    @State private var isLoading = false

    /// Filtered actions based on search text (client-side filtering)
    private var filteredActions: [ActionLogItem] {
        guard !searchText.isEmpty else {
            return actions
        }

        let searchLowercased = searchText.localizedLowercase
        return actions.filter { item in
            item.searchableText.contains(searchLowercased)
        }
    }

    var body: some View {
        List(filteredActions) { item in
            VStack(alignment: .leading, spacing: 4) {
                // Action name and entity
                Text(item.displayName)
                    .font(.headline)

                // Detailed action description with cache indicator
                HStack(spacing: 4) {
                    if item.hasCacheHit {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .foregroundColor(.blue)
                            .accessibilityLabel("Cached")
                    }
                    Text(item.detailDescription)
                        .font(.body)
                        .foregroundColor(item.hasCacheHit ? .blue : .green)
                }

                // Timestamp
                Text(item.timestamp.formatted(date: .numeric, time: .standard))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .searchable(
            text: $searchText,
            prompt: "Search actions..."
        )
        .navigationTitle("Actions (\(filteredActions.count))")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await loadActions()
                    }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
            }

            ToolbarItem(placement: .secondaryAction) {
                ShareLink(
                    item: exportAsText(),
                    preview: SharePreview(
                        "HomeKit_Actions_\(Date().ISO8601Format()).txt",
                        image: Image(systemName: "doc.text")
                    )
                )
                .disabled(actions.isEmpty)
            }

            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    Task {
                        await clearActions()
                    }
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .disabled(actions.isEmpty || isLoading)
            }
        }
        .refreshable {
            await loadActions()
        }
        .onAppear {
            Task {
                await loadActions()
            }
        }
        .overlay {
            if isLoading && actions.isEmpty {
                ProgressView()
            }
        }
    }

    private func loadActions() async {
        isLoading = true
        defer { isLoading = false }

        do {
            actions = try await client.getActions()
        } catch {
            // TODO: Show error alert
            print("Failed to load actions: \(error)")
        }
    }

    private func clearActions() async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await client.clearActions()
            actions = []
        } catch {
            // TODO: Show error alert
            print("Failed to clear actions: \(error)")
        }
    }

    private func exportAsText() -> String {
        let header = """
        HomeKit Action Log
        Exported: \(Date().formatted(date: .long, time: .standard))
        Total Actions: \(actions.count)
        =====================================

        """

        let entries = actions.map { item in
            let status = item.hasCacheHit ? "✅ Cached" : "🆕 Fresh (no cache hit)"
            return """
            [\(item.timestamp.formatted(date: .numeric, time: .standard))] \(item.displayName)
            Action: \(item.detailDescription)
            Entity: \(item.action.entityId)
            Status: \(status)

            """
        }.joined(separator: "\n")

        return header + entries
    }
}

#Preview {
    NavigationStack {
        ActionsListView(client: FlowKitClient(url: URL(string: "http://localhost:8080")!))
    }
}

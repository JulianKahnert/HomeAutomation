//
//  ActionsView.swift
//  ControllerFeatures
//
//  TCA-based actions list view
//

import ComposableArchitecture
import HAModels
import SwiftUI

struct ActionsView: View {
    @Bindable var store: StoreOf<ActionsFeature>

    var body: some View {
        NavigationStack {
            List {
                ForEach(store.filteredActions) { item in
                    actionRow(item)
                }
            }
            .searchable(
                text: $store.searchText,
                prompt: "Search actions..."
            )
            .navigationTitle("Actions (\(store.filteredActions.count))")
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
                        item: exportAsText(),
                        preview: SharePreview(
                            "HomeKit_Actions_\(Date().ISO8601Format()).txt",
                            image: Image(systemName: "doc.text")
                        )
                    )
                    .disabled(store.actions.isEmpty)
                }

                ToolbarItem(placement: .secondaryAction) {
                    Button(role: .destructive) {
                        store.send(.clearActions)
                    } label: {
                        Label("Clear All", systemImage: "trash")
                    }
                    .disabled(store.actions.isEmpty || store.isLoading)
                }
            }
            .refreshable {
                store.send(.refresh)
            }
            .onAppear {
                store.send(.onAppear)
            }
            .overlay {
                if store.isLoading && store.actions.isEmpty {
                    ProgressView()
                } else if store.actions.isEmpty && !store.isLoading {
                    ContentUnavailableView(
                        "No Actions",
                        systemImage: "list.bullet.clipboard",
                        description: Text("Actions will appear here")
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func actionRow(_ item: ActionLogItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Action name and entity
            Text(item.displayName)
                .font(.headline)

            // Detailed action description with cache indicator
            HStack(spacing: 4) {
                Image(systemName: "internaldrive")
                    .opacity(item.hasCacheHit ? 1 : 0)
                Text(item.detailDescription)
                    .font(.body)
            }
            .foregroundColor(item.hasCacheHit ? Color.yellow : nil)

            // Timestamp
            Text(item.timestamp.formatted(date: .numeric, time: .standard))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func exportAsText() -> String {
        let header = """
        HomeKit Action Log
        Exported: \(Date().formatted(date: .long, time: .standard))
        Total Actions: \(store.actions.count)
        =====================================

        """

        let entries = store.actions.map { item in
            let status = item.hasCacheHit ? "✅ Cached" : "🆕 Fresh (no cache hit)"
            return """
            [\(item.timestamp.formatted(date: .numeric, time: .standard))] \(item.displayName)
            Action: \(item.detailDescription)
            Entity: \(item.entityId)
            Status: \(status)

            """
        }.joined(separator: "\n")

        return header + entries
    }
}

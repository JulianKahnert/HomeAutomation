//
//  ActionsListView.swift
//
//
//  Created by Julian Kahnert on 14.11.25.
//

import HAModels
import SwiftUI

struct ActionsListView: View {
    @State private var logger = ActionLogger.shared
    @State private var searchText = ""

    /// Filtered actions based on search text
    private var filteredActions: [ActionLogItem] {
        guard !searchText.isEmpty else {
            return logger.actions
        }

        let searchLowercased = searchText.localizedLowercase
        return logger.actions.filter { item in
            item.searchableText.contains(searchLowercased)
        }
    }

    var body: some View {
        List(filteredActions) { item in
            VStack(alignment: .leading, spacing: 4) {
                // Action name and entity
                Text(item.displayName)
                    .font(.headline)

                // Detailed action description
                Text(item.detailDescription)
                    .font(.body)
                    .foregroundColor(item.hasCacheHit ? .primary : .green)

                // Timestamp
                Text(item.timestamp.formatted(date: .numeric, time: .standard))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search actions..."
        )
        .navigationTitle("Actions (\(filteredActions.count))")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(
                    item: logger.exportAsText(),
                    preview: SharePreview(
                        "HomeKit_Actions_\(Date().ISO8601Format()).txt",
                        image: Image(systemName: "doc.text")
                    )
                )
                .disabled(logger.actions.isEmpty)
            }

            ToolbarItem(placement: .secondaryAction) {
                Button(role: .destructive) {
                    logger.clear()
                } label: {
                    Label("Clear All", systemImage: "trash")
                }
                .disabled(logger.actions.isEmpty)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ActionsListView()
    }
}

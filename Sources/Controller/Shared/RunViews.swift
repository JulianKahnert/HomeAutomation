//
//  RunViews.swift
//  Controller
//

import HAModels
import SwiftUI

/// Outcome or command status as a tinted SF Symbol label, the way system lists show state.
struct StatusLabel: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(color)
    }
}

extension StatusLabel {
    init(outcome: AutomationRun.Outcome) {
        switch outcome {
        case .running: self.init(text: outcome.label, systemImage: "play.circle.fill", color: .green)
        case .completed: self.init(text: outcome.label, systemImage: "checkmark.circle.fill", color: .accentColor)
        case .failed, .interrupted: self.init(text: outcome.label, systemImage: "exclamationmark.triangle.fill", color: .red)
        case .superseded, .stopped: self.init(text: outcome.label, systemImage: "stop.circle", color: .secondary)
        }
    }

    init(status: ActionLogItem.Status) {
        switch status {
        case .executed: self.init(text: "Fresh", systemImage: "bolt.fill", color: .green)
        case .cacheHit: self.init(text: "Cache", systemImage: "arrow.uturn.backward.circle", color: .yellow)
        case .failed: self.init(text: "Failed", systemImage: "exclamationmark.triangle.fill", color: .red)
        }
    }
}

struct RunRow: View {
    let run: AutomationRun
    var showsAutomationName = true

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                if showsAutomationName {
                    Text(run.automationName)
                }
                Text(run.trigger.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(run.startedAt, format: .dateTime.weekday().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            StatusLabel(outcome: run.outcome)
        }
    }
}

struct ActionRow: View {
    let item: ActionLogItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.detailDescription)
                    .font(.body.monospaced())
                Text("\(item.entityId.name) (\(item.entityId.placeId))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(item.timestamp, format: .dateTime.hour().minute().second())
                .font(.caption)
                .foregroundStyle(.secondary)
            if let status = item.status {
                StatusLabel(status: status)
            }
        }
    }
}

//
//  RunViews.swift
//  Controller
//

import HAModels
import SwiftUI

struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(color.opacity(0.15), in: .capsule)
    }
}

extension Pill {
    init(outcome: AutomationRun.Outcome) {
        switch outcome {
        case .running: self.init(text: outcome.label, color: .green)
        case .completed: self.init(text: outcome.label, color: .accentColor)
        case .failed, .interrupted: self.init(text: outcome.label, color: .red)
        case .superseded, .stopped: self.init(text: outcome.label, color: .secondary)
        }
    }

    init(status: ActionLogItem.Status) {
        switch status {
        case .executed: self.init(text: "Fresh", color: .green)
        case .cacheHit: self.init(text: "Cache", color: .yellow)
        case .failed: self.init(text: "Failed", color: .red)
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
            Pill(outcome: run.outcome)
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
                Pill(status: status)
            }
        }
    }
}

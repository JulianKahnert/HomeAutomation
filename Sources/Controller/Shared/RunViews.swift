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
            // Forms otherwise lay a label out like a row title, with a wide icon column.
            .labelStyle(.titleAndIcon)
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
        // Without this the separator starts at the status label, the row's last text.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
    }
}

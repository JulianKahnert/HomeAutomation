//
//  FireplaceQuestionConfiguration.swift
//  FlowKit Controller
//

import Controller
import SwiftUI
import WidgetKit

/// The fireplace question "Ist der Kamin noch an?" with its answers on the Lock Screen and in the Dynamic Island.
struct FireplaceQuestionConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FireplaceAttributes.self) { context in
            FireplaceQuestionLiveActivityView(contentState: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FireplaceQuestionCountdown(contentState: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ist der Kamin noch an?")
                            .font(.headline)
                        FireplaceQuestionButtons()
                    }
                }
            } compactLeading: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                FireplaceQuestionCountdown(contentState: context.state)
            } minimal: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
            }
            .keylineTint(.orange)
        }
    }
}

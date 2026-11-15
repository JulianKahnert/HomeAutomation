//
//  WindowOpenPushConfiguration.swift
//  FlowKit Controller
//
//  Created by Julian Kahnert on 06.03.25.
//

#if os(iOS)
import Controller
import SwiftUI
import WidgetKit

struct WindowOpenPushConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WindowAttributes.self) { context in
            // The Lock Screen, the banner, StandBy and the Mac menu bar get the `.medium` family;
            // the Watch Smart Stack gets `.small`.
            WindowOpenActivityContent(contentState: context.state)
        } dynamicIsland: { context in
            let presentation = WindowActivityPresentation(contentState: context.state,
                                                          rowBudget: WindowActivityPresentation.expandedRowBudget)
            // Create the presentations that appear in the Dynamic Island.
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    WindowOpenLiveActivityView(contentState: context.state,
                                               rowBudget: WindowActivityPresentation.expandedRowBudget)
                }
            } compactLeading: {
                Label("\(context.state.openCount)", systemImage: "window.vertical.open")
                    .foregroundStyle(presentation.isAnyOverdue ? Color.red : Color.primary)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Label("\(context.state.openCount)", systemImage: "window.vertical.open")
                    .foregroundStyle(presentation.isAnyOverdue ? Color.red : Color.primary)
            }
        }
        .supplementalActivityFamilies([.small])
    }
}

/// Picks the layout for the activity family: the compact list (design 1c) for `.medium`, the most
/// urgent window for `.small` on the Watch.
private struct WindowOpenActivityContent: View {
    @Environment(\.activityFamily) private var activityFamily
    let contentState: WindowAttributes.ContentState

    var body: some View {
        switch activityFamily {
        case .small:
            WindowOpenWatchActivityView(contentState: contentState)
        case .medium:
            WindowOpenLiveActivityView(contentState: contentState,
                                       rowBudget: WindowActivityPresentation.lockScreenRowBudget)
        @unknown default:
            WindowOpenLiveActivityView(contentState: contentState,
                                       rowBudget: WindowActivityPresentation.lockScreenRowBudget)
        }
    }
}
#endif

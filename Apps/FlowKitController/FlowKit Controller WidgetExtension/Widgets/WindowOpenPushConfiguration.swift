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
            WindowOpenActivityContent(contentState: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            let presentation = WindowActivityPresentation(contentState: context.state,
                                                          rowBudget: WindowActivityPresentation.expandedRowBudget,
                                                          isStale: context.isStale)
            // Design 1c: leading, trailing and bottom only; the centre region sits over the camera.
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    WindowIslandExpandedLeading(presentation: presentation)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    WindowIslandExpandedTrailing(presentation: presentation)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    WindowIslandExpandedBottom(presentation: presentation)
                }
            } compactLeading: {
                WindowIslandCountBadge(openCount: context.state.openCount, tint: presentation.compactTint)
            } compactTrailing: {
                WindowIslandCompactTrailing(presentation: presentation)
            } minimal: {
                WindowIslandCountBadge(openCount: context.state.openCount, tint: presentation.compactTint)
            }
            .keylineTint(presentation.isAnyOverdue ? Color.red : nil)
        }
        // There is no API to limit `.small` to the Watch, so CarPlay may show it too.
        .supplementalActivityFamilies([.small])
    }
}

/// Picks the layout for the activity family: the compact list (design 1c) for `.medium`, the most
/// urgent window for `.small` on the Watch.
private struct WindowOpenActivityContent: View {
    @Environment(\.activityFamily) private var activityFamily
    let contentState: WindowAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if activityFamily == .small {
            WindowOpenWatchActivityView(contentState: contentState, isStale: isStale)
        } else {
            WindowOpenLiveActivityView(contentState: contentState,
                                       rowBudget: WindowActivityPresentation.lockScreenRowBudget,
                                       isStale: isStale)
        }
    }
}
#endif

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
            // Create the presentation that appears on the Lock Screen and as a
            // banner on the Home Screen of devices that don't support the
            // Dynamic Island.
            WindowOpenLiveActivityView(contentState: context.state,
                                       rowBudget: WindowActivityPresentation.lockScreenRowBudget)
        } dynamicIsland: { context in
            let presentation = WindowActivityPresentation(contentState: context.state,
                                                          rowBudget: WindowActivityPresentation.expandedRowBudget)
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
                WindowIslandCountBadge(contentState: context.state, presentation: presentation)
            } compactTrailing: {
                WindowIslandCompactTrailing(presentation: presentation)
            } minimal: {
                WindowIslandCountBadge(contentState: context.state, presentation: presentation)
            }
            .keylineTint(presentation.isAnyOverdue ? Color.red : nil)
        }
    }
}
#endif

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
                                       rowBudget: WindowActivityPresentation.lockScreenRowBudget,
                                       isStale: context.isStale)
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
    }
}
#endif

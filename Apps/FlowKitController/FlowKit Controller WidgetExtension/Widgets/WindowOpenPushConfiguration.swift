//
//  WindowOpenPushConfiguration.swift
//  FlowKit Controller
//
//  Created by Julian Kahnert on 06.03.25.
//

#if os(iOS)
import SwiftUI
import WidgetKit

struct WindowOpenPushConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WindowAttributes.self) { context in
            // Create the presentation that appears on the Lock Screen and as a
            // banner on the Home Screen of devices that don't support the
            // Dynamic Island.
            WindowOpenLiveActivityView(contentState: context.state)
        } dynamicIsland: { context in
            // Create the presentations that appear in the Dynamic Island.
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    WindowOpenLiveActivityView(contentState: context.state)
                }
            } compactLeading: {
                let shouldClose = context.state.windowStates.contains { Date() > $0.end }
                Label("\(context.state.windowStates.count)", systemImage: "window.vertical.open")
                    .foregroundStyle(shouldClose ? Color.red : Color.primary)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                let shouldClose = context.state.windowStates.contains { Date() > $0.end }
                Label("\(context.state.windowStates.count)", systemImage: "window.vertical.open")
                    .foregroundStyle(shouldClose ? Color.red : Color.primary)
            }
        }
    }
}
#endif

//
//  WindowOpenPushConfiguration.swift
//  FlowKit Controller
//
//  Created by Julian Kahnert on 06.03.25.
//

import SwiftUI
import WidgetKit

struct WindowOpenPushConfiguration: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WindowOpenAttributes.self) { context in
            // Create the presentation that appears on the Lock Screen and as a
            // banner on the Home Screen of devices that don't support the
            // Dynamic Island.
            WindowOpenLiveActivityView(contentState: context.state)
                .activityBackgroundTint(Color.gray.opacity(0.6))
        } dynamicIsland: { context in
            // Create the presentations that appear in the Dynamic Island.
            DynamicIsland {
                // Create the expanded presentation.
//                expandedContent(
//                    hero: context.attributes.hero,
//                    contentState: context.state,
//                    isStale: context.isStale
//                )
                DynamicIslandExpandedRegion(.bottom) {
                    
                    Text("Dynamic Island")
                }
            } compactLeading: {
                // Create the compact leading presentation.
//                Avatar(hero: context.attributes.hero, includeBackground: true)
//                    .accessibilityLabel("The avatar of \(context.attributes.hero.name).")
                Text("L\(context.state.windowStates.count)")
            } compactTrailing: {
                // Create the compact trailing presentation.
//                ProgressView(value: context.state.currentHealthLevel, total: 1) {
//                    let healthLevel = Int(context.state.currentHealthLevel * 100)
//                    Text("\(healthLevel)")
//                        .accessibilityLabel("Health level at \(healthLevel) percent.")
//                }
//                .progressViewStyle(.circular)
//                .tint(context.state.currentHealthLevel <= 0.2 ? Color.red : Color.green)
                Text("T\(context.state.windowStates.count)")
            } minimal: {
                // Create the minimal presentation.
//                ProgressView(value: context.state.currentHealthLevel, total: 1) {
//                    Avatar(hero: context.attributes.hero, includeBackground: false)
//                        .accessibilityLabel("The avatar of \(context.attributes.hero.name).")
//                }
//                .progressViewStyle(.circular)
//                .tint(context.state.currentHealthLevel <= 0.2 ? Color.red : Color.green)
                Text("M\(context.state.windowStates.count)")
            }
            
        }
    }
}

//#Preview(as: WidgetFamily.systemSmall) {
//    WindowOpenPushConfiguration()
//} timeline: {
//    WindowOpenAttributes.ContentState(windowStates: [
//        .init(name: "window1", opened: Date(), maxOpenDuration: 60)
//    ])
////    WindowOpenAttributes()
////    CaffeineLogEntry.log1
////    CaffeineLogEntry.log2
////    CaffeineLogEntry.log3
////    CaffeineLogEntry.log4
//}

//
//  WindowOpenLiveActivityView.swift
//  FlowKit Controller
//
//  Created by Julian Kahnert on 06.03.25.
//

#if canImport(ActivityKit)

import SwiftUI

struct WindowOpenLiveActivityView: View {
    let contentState: WindowOpenAttributes.ContentState
    
    public var body: some View {
        VStack(alignment: .leading) {
            ForEach(contentState.windowStates, id: \.self) { windowState in
                let value = getNormalizedValue(for: windowState)
                ProgressView(windowState.name, value: value)
                    .progressViewStyle(.linear)
                    .foregroundStyle(Color.black)
                    .tint(value <= 1 ? Color.accentColor : Color.red)
            }
        }
        .padding()
    }
    
    private func getNormalizedValue(for windowState: WindowOpenAttributes.ContentState.WindowState) -> Double {
        
        // time in percent the
        return Date().timeIntervalSince(windowState.opened) / windowState.maxOpenDuration
    }
}

#Preview {
    let date = Date()
    // 3 minutes
    let maxOpenDuration: TimeInterval = 60 * 3
    WindowOpenLiveActivityView(contentState:
            .init(windowStates: [
                // just opened
                .init(name: "window1", opened: date, maxOpenDuration: maxOpenDuration),
                // opened 1 minute ago
                .init(name: "window2", opened: date.addingTimeInterval(-1 * 60), maxOpenDuration: maxOpenDuration),
                // opened 2 minute ago
                .init(name: "window3", opened: date.addingTimeInterval(-2 * 60), maxOpenDuration: maxOpenDuration),
                // opened 5 minute ago
                .init(name: "window4", opened: date.addingTimeInterval(-5 * 60), maxOpenDuration: maxOpenDuration)
            ])
    )
}
#endif

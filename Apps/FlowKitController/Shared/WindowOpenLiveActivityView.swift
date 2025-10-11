//
//  WindowOpenLiveActivityView.swift
//  FlowKit Controller
//
//  Created by Julian Kahnert on 06.03.25.
//

#if os(iOS)
import SwiftUI

struct WindowOpenLiveActivityView: View {
    let contentState: WindowAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(contentState.windowStates, id: \.hashValue) { windowState in
                GeometryReader { geometry in
                    HStack(spacing: 12) {
                        ProgressView(timerInterval: windowState.opened...windowState.end, countsDown: false)
                            .tint(Date() <= windowState.end ? Color.accentColor : Color.red)
                            .frame(width: geometry.size.width / 3 - 6)

                        Text(windowState.name)
                            .font(.body)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(width: geometry.size.width * 2 / 3 - 6, alignment: .leading)
                    }
                }
                .frame(height: 20)
            }
        }
        .padding()
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

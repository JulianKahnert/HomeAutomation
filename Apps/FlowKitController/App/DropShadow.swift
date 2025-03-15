//
//  DropShadow.swift
//  FlowKit Controller
//
//  Created by Julian Kahnert on 14.03.25.
//

import SwiftUI

extension Color {
    static var systemBackground: Color {
        #if canImport(UIKit)
        Color(UIColor.systemBackground)
        #else
        Color(NSColor.textBackgroundColor)
        #endif
    }
}

struct DropShadow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor.systemBackground))
            )
            .compositingGroup()
            .shadow(color: Color.gray.opacity(0.7),
                    radius: 8,
                    x: 0,
                    y: 0)
            .padding()
    }
}

#if DEBUG
#Preview("DropShadow light", traits: .fixedLayout(width: 400, height: 500)) {
    Text("Test")
        .modifier(DropShadow())
}

#Preview("DropShadow dark", traits: .fixedLayout(width: 400, height: 500)) {
    Text("Test")
        .modifier(DropShadow())
        .preferredColorScheme(.dark)
}
#endif

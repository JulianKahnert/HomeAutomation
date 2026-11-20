//
//  HeatingHatch.swift
//  ControllerFeatures
//
//  The hatched box for "no actual value": a room bar in the overview, a cell in the heatmap
//

import SwiftUI

struct HeatingHatch: View {
    var isSelected = false
    var showsMark = true

    var body: some View {
        ZStack {
            Canvas { context, size in
                var path = Path()
                var x = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += 5
                }
                context.stroke(path, with: .color(.secondary.opacity(0.7)), lineWidth: 1)
            }
            Rectangle()
                .strokeBorder(isSelected ? Color.primary : .secondary, style: StrokeStyle(lineWidth: isSelected ? 2 : 1, dash: [3, 2]))
            if showsMark {
                Text("?").font(.headline).foregroundStyle(.primary)
            }
        }
    }
}

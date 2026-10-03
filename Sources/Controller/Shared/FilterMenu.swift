//
//  FilterMenu.swift
//  Controller
//

import SwiftUI

/// Toolbar filter the way Mail shows it: a menu with one checkmarked option, filled while a filter is on.
struct FilterMenu<Selection: Hashable, Options: View>: View {
    @Binding var selection: Selection
    let isActive: Bool
    @ViewBuilder let options: () -> Options

    var body: some View {
        Menu {
            Picker("Filter", selection: $selection, content: options)
        } label: {
            Label("Filter", systemImage: isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }
}

#Preview {
    @Previewable @State var selection = "All"
    NavigationStack {
        List {
            Text(selection)
        }
        .toolbar {
            FilterMenu(selection: $selection, isActive: selection != "All") {
                ForEach(["All", "Failed"], id: \.self) { Text($0).tag($0) }
            }
        }
    }
}

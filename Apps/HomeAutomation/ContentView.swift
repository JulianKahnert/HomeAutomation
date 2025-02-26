//
//  ContentView.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 22.02.25.
//

import SwiftUI

let client = AutomationClient(url: URL(string: "http://0.0.0.0:8080/")!)

typealias Automation = Components.Schemas.Automation
extension Automation: Identifiable {
    var id: String { name }
}

extension Bool {
    var inverted: Bool { !self }
}

struct ContentView: View {
    @State private var automations: [Automation] = []

    var body: some View {
        List(automations) { automation in
            view(for: automation)
        }
//        List {
//            Section {
//                ForEach(automations.filter(\.isActive)) { automation in
//                    view(for: automation)
//                }
//            }
//            Section {
//                ForEach(automations.filter(\.isActive.inverted)) { automation in
//                    view(for: automation)
//                }
//            }
//        }
        .refreshable {
            await updateAutomations()
        }
        .task {
            await updateAutomations()
        }
    }

    @ViewBuilder
    func view(for automation: Automation) -> some View {
        VStack(alignment: .leading) {
            Text(automation.name)
            HStack {
                Image(systemName: "circle.fill")
                    .foregroundStyle(automation.isRunning ? Color.green : Color.gray.opacity(0.3))
                Spacer()
                Toggle("", isOn: Binding<Bool>(get: {
                    automation.isActive
                }, set: { value in
                    guard value != automation.isActive else { return }
                    Task {
                        await toggleActive(value, automationName: automation.name)
                    }
                }))
            }
        }
    }

    func updateAutomations() async {
        do {
            self.automations = try await client.getAutomations()
        } catch {
            assertionFailure()
        }
    }

    func toggleActive(_ value: Bool, automationName: String) async {
        do {
            if value {
                try await client.activate(automation: automationName)
            } else {
                try await client.deactivate(automation: automationName)
            }
            self.automations = try await client.getAutomations()
        } catch {
            assertionFailure()
        }
    }
}

#Preview {
    ContentView()
}

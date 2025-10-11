//
//  AutomationStore.swift
//  FlowKit Controller
//
//  Created by Claude Code on 11.10.25.
//

import Foundation
import Observation

@Observable
final class AutomationStore {
    var automations: [Automation] = []

    func update(automation: Automation) {
        if let index = automations.firstIndex(where: { $0.id == automation.id }) {
            automations[index] = automation
        }
    }

    func updateAll(_ newAutomations: [Automation]) {
        self.automations = newAutomations
    }

    func automation(withId id: String) -> Automation? {
        automations.first(where: { $0.id == id })
    }
}

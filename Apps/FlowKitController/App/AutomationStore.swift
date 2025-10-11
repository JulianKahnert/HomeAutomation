import Combine
import Dependencies
import Foundation

final class AutomationStore: ObservableObject {
    @Published var automations: [Automation] = []

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

extension AutomationStore: DependencyKey {
    static let liveValue = AutomationStore()
}

extension DependencyValues {
    var automationStore: AutomationStore {
        get { self[AutomationStore.self] }
        set { self[AutomationStore.self] = newValue }
    }
}

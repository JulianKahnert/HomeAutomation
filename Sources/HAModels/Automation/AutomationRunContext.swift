//
//  AutomationRunContext.swift
//  HAModels
//

import Foundation

/// Carries the current `AutomationRun` down to what an automation does: its id to the commands it sends,
/// and the event that started it to `execute`, whose signature has no room for it.
public enum AutomationRunContext {
    @TaskLocal public static var runId: UUID?
    @TaskLocal public static var event: HomeEvent?

    /// Whether the current run was started by a configuration deploy.
    public static var isConfigDeploy: Bool {
        guard case .configDeployed = event else { return false }
        return true
    }
}

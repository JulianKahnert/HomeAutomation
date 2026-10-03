//
//  AutomationRunContext.swift
//  HAModels
//

import Foundation

/// Carries the current `AutomationRun` id down to the commands an automation sends.
public enum AutomationRunContext {
    @TaskLocal public static var runId: UUID?
}

//
//  AutomationInfo+Display.swift
//  Controller
//

import Foundation
import HAModels

extension AutomationInfo {
    /// Label, symbol and trigger configuration per automation type; keys match the server's type names.
    private static let typeDisplay: [String: (label: String, systemImage: String, trigger: String)] = [
        "CreateScene": ("Scene", "sparkles", "Manual"),
        "EnergyLowPrice": ("Energy Price", "bolt", "Electricity price"),
        "GardenWatering": ("Garden", "drop", "Schedule"),
        "HealthCheck": ("System", "stethoscope", "Every minute"),
        "MaintenanceAutomation": ("System", "wrench.and.screwdriver", "Schedule"),
        "MotionAtNight": ("Motion", "figure.walk", "Motion sensor"),
        "RestartSystem": ("System", "arrow.clockwise", "Schedule"),
        "SetLightProperties": ("Light", "lightbulb", "Light change"),
        "TriggerScene": ("Scene", "sparkles", "Device change"),
        "Turn": ("Schedule", "clock", "Schedule"),
        "TurnOnForDuration": ("Light", "timer", "Device change"),
        "UpsertScene": ("Scene", "sparkles", "Manual"),
        "WindowOpen": ("Window", "window.casement", "Window contact")
    ]

    var typeLabel: String {
        type.flatMap { Self.typeDisplay[$0]?.label } ?? "Other"
    }

    var systemImage: String {
        type.flatMap { Self.typeDisplay[$0]?.systemImage } ?? "gearshape"
    }

    var triggerDescription: String {
        type.flatMap { Self.typeDisplay[$0]?.trigger } ?? "Unknown trigger"
    }

    /// "last 21:05 · Motion · Eve Motion (Hallway)", or the trigger configuration before the first run.
    var subtitle: String {
        guard let lastRun else { return triggerDescription }
        return "last \(lastRun.startedAt.formatted(date: .omitted, time: .shortened)) · \(lastRun.trigger.summary)"
    }
}

extension AutomationRun.Outcome {
    var label: String {
        switch self {
        case .running: return "Running"
        case .completed: return "Completed"
        case .superseded: return "Superseded"
        case .stopped: return "Stopped"
        case .failed: return "Failed"
        case .interrupted: return "Interrupted"
        }
    }
}

//
//  AutomationInfo+Display.swift
//  Controller
//

import Foundation
import HAModels

extension AutomationInfo {
    /// Label, symbol and trigger configuration per automation type; keys match the server's type names.
    private static let typeDisplay: [String: (label: String.LocalizationValue, systemImage: String, trigger: String.LocalizationValue)] = [
        "CreateScene": ("Scene", "sparkles", "Manual"),
        "DatabaseCleanup": ("System", "externaldrive.badge.checkmark", "Hourly"),
        "EnergyLowPrice": ("Energy Price", "bolt", "Electricity price"),
        "FireplaceTimeout": ("Fireplace", "flame", "Every minute"),
        "GardenWatering": ("Garden", "drop", "Schedule"),
        "HealthCheck": ("System", "stethoscope", "Every minute"),
        "MaintenanceAutomation": ("System", "wrench.and.screwdriver", "Schedule"),
        "MotionAtNight": ("Motion", "figure.walk", "Motion Sensor"),
        "RestartSystem": ("System", "arrow.clockwise", "Schedule"),
        "RoomHeating": ("Heating", "thermometer.medium", "Plan"),
        "SetLightProperties": ("Light", "lightbulb", "Light change"),
        "TriggerScene": ("Schedule", "clock", "Schedule"),
        "Turn": ("Schedule", "clock", "Schedule"),
        "TurnOnForDuration": ("Light", "timer", "Device change"),
        "UpsertScene": ("Scene", "sparkles", "Manual"),
        "WindowOpen": ("Window", "window.casement", "Window contact"),
        "WindowProjection": ("Window", "rectangle.badge.clock", "Window deadlines")
    ]

    var typeLabel: String {
        String(localized: type.flatMap { Self.typeDisplay[$0]?.label } ?? "Other", bundle: .module)
    }

    var systemImage: String {
        type.flatMap { Self.typeDisplay[$0]?.systemImage } ?? "gearshape"
    }

    var triggerDescription: String {
        String(localized: type.flatMap { Self.typeDisplay[$0]?.trigger } ?? "Unknown trigger", bundle: .module)
    }

    /// "last 21:05 · Motion · Eve Motion (Hallway)", or the trigger configuration before the first run.
    var subtitle: String {
        guard let lastRun else { return triggerDescription }
        return String(localized: "last \(lastRun.startedAt.formatted(date: .omitted, time: .shortened)) · \(lastRun.trigger.summary)", bundle: .module)
    }
}

extension AutomationRun.Outcome {
    var label: String {
        switch self {
        case .running: return String(localized: "Running", bundle: .module)
        case .completed: return String(localized: "Completed", bundle: .module)
        case .superseded: return String(localized: "Superseded", bundle: .module)
        case .stopped: return String(localized: "Stopped", bundle: .module)
        case .failed: return String(localized: "Failed", bundle: .module)
        case .interrupted: return String(localized: "Interrupted", bundle: .module)
        }
    }
}

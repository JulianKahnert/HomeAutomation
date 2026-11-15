//
//  DebugLogging.swift
//  Shared
//

import Foundation
import Logging

/// The `HA_DEBUG_LOGGING` switch that turns on debug logs in the server and the adapter, off by default.
///
/// The environment variable wins, so it can also switch the logs off. The adapter is a sandboxed GUI app
/// where environment variables are awkward, so it also reads the key from `UserDefaults`
/// (`defaults write de.juliankahnert.HomeKitAdapterApp HA_DEBUG_LOGGING -bool YES`).
public enum DebugLogging {
    public static let key = "HA_DEBUG_LOGGING"

    public static func isEnabled(environment: [String: String] = ProcessInfo.processInfo.environment,
                                 defaults: UserDefaults? = nil) -> Bool {
        if let value = environment[key] {
            return ["1", "true", "yes", "on"].contains(value.trimmingCharacters(in: .whitespaces).lowercased())
        }
        return defaults?.bool(forKey: key) ?? false
    }

    /// `level` lowered to `debug` when the switch is on; a more verbose `level` (`trace`) stays.
    public static func level(_ level: Logger.Level, enabled: Bool) -> Logger.Level {
        enabled ? min(level, .debug) : level
    }
}

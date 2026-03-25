//
//  LogFileDependency.swift
//  ControllerFeatures
//
//  Dependency for reading and parsing file-based logs
//

import Dependencies
import DependenciesMacros
import Foundation

// MARK: - Log Entry Model

struct LogEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: String
    let label: String
    let message: String
    let rawLine: String
}

// MARK: - LogFile Dependency

@DependencyClient
struct LogFileDependency: Sendable {
    /// Read log entries from file-based logs within a time window.
    var readLogEntries: @Sendable (_ since: Date) async -> [LogEntry] = { _ in [] }

    /// Format log entries as plain text for export.
    var exportLogText: @Sendable (_ entries: [LogEntry]) -> String = { _ in "" }
}

// MARK: - Dependency Key Implementation

extension LogFileDependency: TestDependencyKey {
    static let testValue = Self()

    static let previewValue = Self(
        readLogEntries: { _ in
            let now = Date()
            return [
                LogEntry(id: UUID(), timestamp: now, level: "info", label: "AppFeature", message: "Scene phase: inactive -> active", rawLine: ""),
                LogEntry(id: UUID(), timestamp: now.addingTimeInterval(-5), level: "info", label: "LiveActivityDependency", message: "activityUpdates emitted activity: id=ABC123", rawLine: ""),
                LogEntry(id: UUID(), timestamp: now.addingTimeInterval(-10), level: "error", label: "AppFeature", message: "Failed to register push token", rawLine: ""),
                LogEntry(id: UUID(), timestamp: now.addingTimeInterval(-60), level: "debug", label: "LiveActivityDependency", message: "hasActiveActivities: 1 active", rawLine: ""),
                LogEntry(id: UUID(), timestamp: now.addingTimeInterval(-120), level: "info", label: "AppDelegate", message: "App launched (may be foreground or background)", rawLine: ""),
            ]
        },
        exportLogText: { entries in
            entries.map(\.rawLine).joined(separator: "\n")
        }
    )
}

extension LogFileDependency: DependencyKey {
    static let liveValue: Self = {
        let dateFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
            df.locale = Locale(identifier: "en_US_POSIX")
            return df
        }()

        let fileDateFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.timeZone = .current
            return df
        }()

        return Self(
            readLogEntries: { since in
                let basePath = URL.documentsDirectory
                let maxEntries = 5000

                // Collect file names for the relevant date range
                var fileNames: [String] = []
                var date = since
                let now = Date()
                while date <= now {
                    fileNames.append(fileDateFormatter.string(from: date) + ".txt")
                    date = date.addingTimeInterval(86400)
                }
                // Always include today
                let todayFileName = fileDateFormatter.string(from: now) + ".txt"
                if !fileNames.contains(todayFileName) {
                    fileNames.append(todayFileName)
                }

                var entries: [LogEntry] = []
                for fileName in fileNames {
                    let fileURL = basePath.appendingPathComponent(fileName)
                    guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                        continue
                    }

                    for line in content.components(separatedBy: .newlines) where !line.isEmpty {
                        let entry = parseLine(line, dateFormatter: dateFormatter)
                        if entry.timestamp >= since {
                            entries.append(entry)
                        }
                    }
                }

                // Sort newest first, cap at maxEntries
                entries.sort { $0.timestamp > $1.timestamp }
                if entries.count > maxEntries {
                    entries = Array(entries.prefix(maxEntries))
                }
                return entries
            },
            exportLogText: { entries in
                // Export in chronological order (oldest first)
                entries.reversed().map(\.rawLine).joined(separator: "\n")
            }
        )
    }()

    private static func parseLine(_ line: String, dateFormatter: DateFormatter) -> LogEntry {
        // Format: "YYYY-MM-DDTHH:MM:SS+ZZZZ level label :metadata message"
        let components = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)

        guard components.count >= 3 else {
            return LogEntry(id: UUID(), timestamp: .distantPast, level: "?", label: "?", message: line, rawLine: line)
        }

        let timestampStr = String(components[0])
        let level = String(components[1])
        let labelAndMessage = String(components[2...].joined(separator: " "))

        let timestamp = dateFormatter.date(from: timestampStr) ?? .distantPast

        // Split label from message at first ":"
        let label: String
        let message: String
        if let colonIndex = labelAndMessage.firstIndex(of: ":") {
            label = String(labelAndMessage[..<colonIndex]).trimmingCharacters(in: .whitespaces)
            let afterColon = labelAndMessage[labelAndMessage.index(after: colonIndex)...]
            message = String(afterColon).trimmingCharacters(in: .whitespaces)
        } else {
            label = labelAndMessage
            message = ""
        }

        return LogEntry(id: UUID(), timestamp: timestamp, level: level, label: label, message: message, rawLine: line)
    }
}

// MARK: - DependencyValues Extension

extension DependencyValues {
    var logFile: LogFileDependency {
        get { self[LogFileDependency.self] }
        set { self[LogFileDependency.self] = newValue }
    }
}

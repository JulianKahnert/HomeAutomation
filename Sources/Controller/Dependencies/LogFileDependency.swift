//
//  LogFileDependency.swift
//  ControllerFeatures
//
//  Dependency for reading JSONL log files written by FileLogHandler
//

import Dependencies
import DependenciesMacros
import Foundation
import Shared

// MARK: - LogFile Dependency

@DependencyClient
struct LogFileDependency: Sendable {
    /// Read log entries from JSONL log files within a time window.
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
                LogEntry(timestamp: now, level: "info", label: "AppFeature", message: "Scene phase: inactive -> active"),
                LogEntry(timestamp: now.addingTimeInterval(-5), level: "info", label: "LiveActivityDependency", message: "activityUpdates emitted activity: id=ABC123"),
                LogEntry(timestamp: now.addingTimeInterval(-10), level: "error", label: "AppFeature", message: "Failed to register push token"),
                LogEntry(timestamp: now.addingTimeInterval(-60), level: "debug", label: "LiveActivityDependency", message: "hasActiveActivities: 1 active"),
                LogEntry(timestamp: now.addingTimeInterval(-120), level: "info", label: "AppDelegate", message: "App launched (may be foreground or background)"),
            ]
        },
        exportLogText: { entries in
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return entries.reversed().map { entry in
                "[\(formatter.string(from: entry.timestamp))] \(entry.level) \(entry.label): \(entry.message)"
            }.joined(separator: "\n")
        }
    )
}

extension LogFileDependency: DependencyKey {
    static let liveValue: Self = {
        let decoder: JSONDecoder = {
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            return d
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
                var fileNames: Set<String> = []
                var date = since
                let now = Date()
                while date <= now {
                    fileNames.insert(fileDateFormatter.string(from: date) + ".txt")
                    date = date.addingTimeInterval(86400)
                }
                fileNames.insert(fileDateFormatter.string(from: now) + ".txt")

                var entries: [LogEntry] = []
                for fileName in fileNames {
                    let fileURL = basePath.appendingPathComponent(fileName)
                    guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                        continue
                    }

                    for line in content.components(separatedBy: .newlines) where !line.isEmpty {
                        guard let data = line.data(using: .utf8),
                              let entry = try? decoder.decode(LogEntry.self, from: data),
                              entry.timestamp >= since else {
                            continue
                        }
                        entries.append(entry)
                    }
                }

                entries.sort { $0.timestamp > $1.timestamp }
                if entries.count > maxEntries {
                    entries = Array(entries.prefix(maxEntries))
                }
                return entries
            },
            exportLogText: { entries in
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                return entries.reversed().map { entry in
                    "[\(formatter.string(from: entry.timestamp))] \(entry.level) \(entry.label): \(entry.message)"
                }.joined(separator: "\n")
            }
        )
    }()
}

// MARK: - DependencyValues Extension

extension DependencyValues {
    var logFile: LogFileDependency {
        get { self[LogFileDependency.self] }
        set { self[LogFileDependency.self] = newValue }
    }
}

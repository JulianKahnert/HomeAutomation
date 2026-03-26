//
//  LogReader.swift
//  Shared
//
//  Reads JSONL log files written by FileLogHandler.
//  Dependencies: Foundation only.
//

import Foundation

/// Reads structured ``LogEntry`` objects from JSONL log files.
public enum LogReader {

    /// Read log entries from JSONL files within a time window.
    /// - Parameters:
    ///   - since: Only return entries at or after this date.
    ///   - basePath: Directory containing the log files (defaults to Documents).
    ///   - maxEntries: Maximum number of entries to return.
    /// - Returns: Entries sorted newest-first, capped at `maxEntries`.
    public static func readEntries(since: Date, basePath: URL = .documentsDirectory, maxEntries: Int = 5000) -> [LogEntry] {
        let fileDateFormatter = DateFormatter()
        fileDateFormatter.dateFormat = "yyyy-MM-dd"
        fileDateFormatter.timeZone = .current

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Collect file names covering the date range
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
    }

    /// Format entries as plain text for export (chronological order).
    public static func exportText(for entries: [LogEntry]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return entries.reversed().map { entry in
            "[\(formatter.string(from: entry.timestamp))] \(entry.level) \(entry.label): \(entry.message)"
        }.joined(separator: "\n")
    }
}

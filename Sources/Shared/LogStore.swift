//
//  LogStore.swift
//  Shared
//

import Foundation

/// Single actor owning log write, read, and retention for daily JSONL files.
///
/// Path resolution order:
///   1. `LOG_DIRECTORY` environment variable
///   2. Platform default (`.documentsDirectory` on Apple OS, `/app/logs` on Linux)
public actor LogStore {
    public static let shared = LogStore()

    private let basePath: URL
    private var fileHandle: FileHandle
    private var nextRotationDate: Date

    private static let fileDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        return f
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = .sortedKeys
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public init(basePath: URL? = nil) {
        let resolvedPath: URL
        if let override = basePath {
            resolvedPath = override
        } else if let envValue = ProcessInfo.processInfo.environment["LOG_DIRECTORY"] {
            resolvedPath = URL(fileURLWithPath: envValue, isDirectory: true)
        } else {
            #if os(iOS) || os(macOS) || os(watchOS) || os(tvOS) || os(visionOS)
            resolvedPath = URL.documentsDirectory
            #else
            resolvedPath = URL(fileURLWithPath: "/app/logs", isDirectory: true)
            #endif
        }

        try? FileManager.default.createDirectory(at: resolvedPath, withIntermediateDirectories: true)
        self.basePath = resolvedPath
        self.fileHandle = Self.openFileHandle(basePath: resolvedPath)
        self.nextRotationDate = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )!
    }

    // MARK: - Write

    public func write(_ string: String) {
        if Date() > nextRotationDate {
            fileHandle = Self.openFileHandle(basePath: basePath)
            nextRotationDate = Calendar.current.nextDate(
                after: Date(),
                matching: DateComponents(hour: 0, minute: 0, second: 0),
                matchingPolicy: .nextTime
            )!
        }
        if let data = string.data(using: .utf8) {
            fileHandle.write(data)
        }
    }

    // MARK: - Read

    public func readEntries(from startDate: Date, to endDate: Date = Date(), maxEntries: Int = 10_000) -> [LogEntry] {
        var fileNames: Set<String> = []
        var date = startDate
        while date <= endDate {
            fileNames.insert(Self.fileDateFormatter.string(from: date) + ".txt")
            date = date.addingTimeInterval(86400)
        }
        fileNames.insert(Self.fileDateFormatter.string(from: endDate) + ".txt")

        var entries: [LogEntry] = []
        for fileName in fileNames {
            let fileURL = basePath.appendingPathComponent(fileName)
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            for line in content.components(separatedBy: .newlines) where !line.isEmpty {
                guard let data = line.data(using: .utf8),
                      let entry = try? Self.decoder.decode(LogEntry.self, from: data),
                      entry.timestamp >= startDate && entry.timestamp < endDate else { continue }
                entries.append(entry)
            }
        }

        entries.sort { $0.timestamp > $1.timestamp }
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        return entries
    }

    // MARK: - Retention

    public func deleteEntries(olderThan cutoff: Date) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: basePath.path) else { return }
        for file in files where file.hasSuffix(".txt") {
            let name = (file as NSString).deletingPathExtension
            guard let fileDate = Self.fileDateFormatter.date(from: name), fileDate < cutoff else { continue }
            try? FileManager.default.removeItem(at: basePath.appendingPathComponent(file))
        }
    }

    // MARK: - Private helpers

    private static func openFileHandle(basePath: URL) -> FileHandle {
        let name = fileDateFormatter.string(from: Date())
        let url = basePath.appendingPathComponent(name).appendingPathExtension("txt")
        if !FileManager.default.fileExists(atPath: url.path) {
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                fatalError("Failed to create log file at \(url.path)")
            }
        }
        do {
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            return handle
        } catch {
            fatalError("Failed to open log file at \(url.path): \(error)")
        }
    }
}

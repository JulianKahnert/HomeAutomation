//
//  LogItemStorage.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 29.10.24.
//

#if canImport(OSLog)
import OSLog

public actor LogItemStorage {
    private let log = Logger(subsystem: "SmartHomeAutomation", category: "LogItemStorage")
    private let store: OSLogStore
    private var lastDate: Date?

    public init() throws {
        self.store = try OSLogStore(scope: .currentProcessIdentifier)
    }

    public func updateEntries() async throws {

        let lastDate = self.lastDate ?? Date().addingTimeInterval(-10)
        log.debug("Get log entries since \(lastDate, privacy: .public)")

        let lastPosition = store.position(date: lastDate)
//        let levels: [OSLogEntryLog.Level] = [.info, .error, .fault] // .debug seems to be skipped
//        let predicate = NSPredicate(format: "(subsystem == %@) && (messageType IN %@)",
//                                    "SmartHomeAutomation",
//                                    levels.map(\.rawValue))
        let predicate = NSPredicate(format: "(subsystem == %@)",
                                    "SmartHomeAutomation")
        let entries = try store.getEntries(at: lastPosition,
                                           matching: predicate)
        var items: [String] = []
        var dates: [Date] = []
        for entry in entries {
            guard entry.date > lastDate else { continue }

            dates.append(entry.date)
            if let log = entry as? OSLogEntryLog {

                let logLevel: String
                switch log.level {
                case .debug:
                    logLevel = "DEBUG"
                case .info:
                    logLevel = "INFO"
                case .error:
                    logLevel = "ERROR"
                case .fault:
                    logLevel = "FAULT"
                case .undefined:
                    logLevel = "UNDEFINED"
                case .notice:
                    logLevel = "NOTICE"
                @unknown default:
                    logLevel = "UNKNOWN"
                }

                items.append("\(entry.date.ISO8601Format(.iso8601(timeZone: .current, includingFractionalSeconds: true))) \(logLevel) \(log.subsystem) \(log.category) \(log.composedMessage)")
            } else {
                items.append("\(entry.date.ISO8601Format(.iso8601(timeZone: .current, includingFractionalSeconds: true))) \(entry.composedMessage)")
            }
        }
//        log.debug("Received entries first \(dates.sorted().first?.ISO8601Format(.iso8601(timeZone: .current, includingFractionalSeconds: true)) ?? "", privacy: .public)")
//        log.debug("Received entries last  \(dates.sorted().last?.ISO8601Format(.iso8601(timeZone: .current, includingFractionalSeconds: true)) ?? "", privacy: .public)")
        self.lastDate = dates.sorted().last ?? lastDate

        guard !items.isEmpty else { return }

        let text = items.joined(separator: "\n").appending("\n")
        let data = Data(text.utf8)
        let fileUrl = getFileUrl()

        do {
            let handle = try FileHandle(forUpdating: fileUrl)
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            try handle.write(contentsOf: data)
        } catch CocoaError.fileNoSuchFile {
            try data.write(to: fileUrl)
        } catch {
            throw error
        }
    }

    private func getFileUrl() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        let date = Date()

        // format date to "2024-10-29-homeautomation-logs.txt"
        let fileUrl = URL.documentsDirectory.appending(path: "\(formatter.string(from: date))-homeautomation-logs.txt")
        log.debug("LogItemStorage fileUrl \(fileUrl.path(), privacy: .public)")
        return fileUrl
    }
}
#endif

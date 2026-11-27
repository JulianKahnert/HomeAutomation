//
//  NoisyEntityWarner.swift
//  HomeAutomationServer
//

import Foundation
import HAApplicationLayer
import HAModels
import Logging
import Shared

/// Pushes a warning when an entity stored more than ``StoragePolicy/noisyEntityRowsPerDay`` rows in
/// the last 24 hours, so a noisy sensor gets a dead band before it fills the database (CO₂ stored
/// 2,300 rows a day). At most once per entity a day; a server restart resets that memory, and the
/// stable push id then replaces the earlier notification instead of adding one.
actor NoisyEntityWarner: Log {
    private let notificationSender: any NotificationSender
    private var lastWarning: [String: Date] = [:]

    init(notificationSender: any NotificationSender) {
        self.notificationSender = notificationSender
    }

    func check(_ entities: any EntityRetentionStore, now: Date) async throws {
        let day = Duration.days(1).timeInterval
        let noisy = try await entities.entitiesWithRowCount(above: StoragePolicy.noisyEntityRowsPerDay, since: now.addingTimeInterval(-day))
        for entity in noisy {
            let key = "\(entity.placeId)|\(entity.serviceName)|\(entity.characteristicType)"
            if let last = lastWarning[key], now.timeIntervalSince(last) < day {
                continue
            }
            lastWarning[key] = now
            log.warning("Noisy entity \(key): \(entity.rows) rows in 24 h")
            do {
                try await notificationSender.sendNotification(
                    title: "Noisy sensor: \(entity.serviceName)",
                    message: "\(entity.placeId) / \(entity.serviceName) (\(entity.characteristicType)) stored \(entity.rows) rows in 24 h, "
                        + "more than \(StoragePolicy.noisyEntityRowsPerDay). Consider a write dead band in the value descriptor.",
                    id: "storage-noise-\(key)"
                )
            } catch {
                log.warning("Failed to send noisy entity warning: \(error)")
            }
        }
    }
}

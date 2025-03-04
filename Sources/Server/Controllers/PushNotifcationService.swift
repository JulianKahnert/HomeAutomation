//
//  PushNotifcationService.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 04.03.25.
//

@preconcurrency import APNSCore
import Fluent
import HAModels
import VaporAPNS

actor PushNotifcationService: NotificationSender {
    let database: any Database
    let apnsClient: APNSGenericClient
    let notificationTopic: String
    let logger: Logger

    init(database: any Database, apnsClient: APNSGenericClient, notificationTopic: String, logger: Logger) {
        self.database = database
        self.apnsClient = apnsClient
        self.notificationTopic = notificationTopic
        self.logger = logger
    }

    func sendNotification(title: String, message: String) async throws {
        let pushDevices = try await PushDevice
            .query(on: database)
            .all()

        let notification = APNSAlertNotification(
            alert: .init(title: .raw(title), body: .raw(message)),
            expiration: .none,
            priority: .immediately,
            topic: notificationTopic
        )

        for pushDevice in pushDevices {
            do {
                try await apnsClient.sendAlertNotification(notification, deviceToken: pushDevice.deviceToken)
            } catch {
                logger.critical("Failed to send push notification to \(pushDevice.deviceToken): \(error.localizedDescription)")
//                try? await PushDevice.query(on: database)
//                    .filter(\.$deviceToken == pushDevice.deviceToken)
//                    .delete()
            }
        }
    }
}

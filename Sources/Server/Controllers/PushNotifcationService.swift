//
//  PushNotifcationService.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 04.03.25.
//

@preconcurrency import APNSCore
import Fluent
import Foundation
import HAModels
import VaporAPNS

actor PushNotifcationService: NotificationSender {
    private static let logger = Logger(label: "PushNotifcationService")

    let database: any Database
    let apnsClient: any APNSClientProtocol & Sendable
    let notificationTopic: String

    init(database: any Database, apnsClient: any APNSClientProtocol & Sendable, notificationTopic: String) {
        self.database = database
        self.apnsClient = apnsClient
        self.notificationTopic = notificationTopic
    }

    func sendNotification(title: String, message: String) async throws {
        let deviceTokens =
            try await DeviceToken
            .query(on: database)
            .filter(\.$tokenType == "pushNotification")
            .all()

        let notification = APNSAlertNotification(
            alert: .init(title: .raw(title), body: .raw(message)),
            expiration: .none,
            priority: .immediately,
            topic: notificationTopic
        )

        for deviceToken in deviceTokens {
            do {
                try await apnsClient.sendAlertNotification(
                    notification, deviceToken: deviceToken.tokenString)
            } catch {
                Self.logger.critical(
                    "Failed to send push notification to \(deviceToken.deviceName) [\(deviceToken.tokenType)]: \(error.localizedDescription)"
                )
                try? await DeviceToken.query(on: database)
                    .filter(\.$tokenString == deviceToken.tokenString)
                    .delete()
            }
        }
    }

    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState)
        async {
        Self.logger.debug("Start or update live activity")

        do {
            let allDeviceTokens =
            try await DeviceToken
                .query(on: database)
                .filter(\.$tokenType != "pushNotification")
                .all()

            Self.logger.debug("Found tokens \(allDeviceTokens.count)")

            var deviceTokens: [DeviceToken] = []
            for token in allDeviceTokens {
                if token.tokenType == "liveActivityUpdate",
                    let date = token.updatedAt ?? token.createdAt,
                   date < Date().addingTimeInterval(-1 * Duration.hours(4).timeInterval),
                    let tokenId = token.id {

                    // delete liveActivityUpdate tokens that are older than 4 hours
                    try await DeviceToken
                        .query(on: database)
                        .filter(\.$id != tokenId)
                        .delete()

                } else {
                    deviceTokens.append(token)
                }
            }

            let deviceMap = Dictionary(grouping: deviceTokens, by: { $0.deviceName })
            for tokens in deviceMap.values {
                assert(tokens.count <= 2, "Found device with more than 2 tokens")

                var usedToken: DeviceToken?
                do {
                    if let updateToken = tokens.first(where: {
                        $0.tokenType == "liveActivityUpdate"
                    }) {
                        Self.logger.info(
                            "Update LiveActivity (on: \(updateToken.deviceName)): \(contentState)")
                        let notification = APNSLiveActivityNotification<ContentState>(
                            expiration: .none,
                            priority: .consideringDevicePower,
                            appID: notificationTopic,
                            contentState: contentState,
                            event: .update,
                            timestamp: Int(Date().timeIntervalSince1970))

                        // if an update token was found, we assume a live activity was found, so we use this token
                        usedToken = updateToken
                        let response = try await apnsClient.sendLiveActivityNotification(
                            notification, deviceToken: updateToken.tokenString)
                        Self.logger.debug("Received send live activity response: \(response)")

                    } else if let startToken = tokens.first(where: {
                        $0.tokenType == "liveActivityStart"
                    }) {
                        Self.logger.info(
                            "Starting LiveActivity (on: \(startToken.deviceName)): \(contentState)")
                        let notification = APNSStartLiveActivityNotification<
                            ContentState, ContentState
                        >(
                            expiration: .none,
                            priority: .immediately,
                            appID: notificationTopic,
                            contentState: contentState,
                            timestamp: Int(Date().timeIntervalSince1970),
                            attributes: contentState,
                            attributesType: "WindowAttributes",
                            alert: APNSAlertNotificationContent(
                                title: .raw("empty"),
                                body: .raw("empty")))

                        // start a new live activity
                        usedToken = startToken
                        try await apnsClient.sendStartLiveActivityNotification(
                            notification, deviceToken: startToken.tokenString)
                    } else {
                        assertionFailure("Should find at least one start token")
                    }
                } catch {
                    if let apnsError = error as? APNSError,
                        let id = apnsError.apnsUniqueID {
                        Self.logger.critical(
                            "[startOrUpdateLiveActivity] Error sending push notification apnsUniqueID: \(id.uuidString)"
                        )
                    }
                    Self.logger.critical(
                        "[startOrUpdateLiveActivity] Failed to send live activity push notification to \(usedToken?.deviceName ?? "") [\(usedToken?.tokenType ?? "")]: \(error.localizedDescription)"
                    )
                    try? await DeviceToken.query(on: database)
                        .filter(\.$tokenString == usedToken?.tokenString ?? "")
                        .delete()
                }
            }

        } catch {
            Self.logger.critical(
                "Failed to fetch push devices in startOrUpdateOpenWindowActivities: \(error)")
            assertionFailure()
        }
    }

    func endAllLiveActivities(ofActivityType activityType: String) async {
        do {
            let deviceTokens =
                try await DeviceToken
                .query(on: database)
                .filter(\.$activityType == activityType)
                .all()

            let contentState = WindowContentState(windowStates: [])
            let notification = APNSLiveActivityNotification<WindowContentState>(
                expiration: .immediately,
                priority: .immediately,
                appID: notificationTopic,
                contentState: contentState,
                event: .end,
                timestamp: Int(Date().timeIntervalSince1970),
                dismissalDate: .immediately)
            Self.logger.info("Sending live activity notification \(notification)")

            for deviceToken in deviceTokens {
                do {
                    let response = try await apnsClient.sendLiveActivityNotification(
                        notification, deviceToken: deviceToken.tokenString)
                    Self.logger.debug("Received send live activity response: \(response)")

                    // delete token when ending the live activity
                    do {
                        try await DeviceToken.query(on: database)
                            .filter(\.$tokenString == deviceToken.tokenString)
                            .delete()
                    } catch {
                        Self.logger.critical("Failed to delete device token: \(error.localizedDescription)")
                    }
                } catch {
                    if let apnsError = error as? APNSError,
                        let id = apnsError.apnsUniqueID {
                        Self.logger.critical(
                            "[endAllLiveActivities] Error sending push notification apnsUniqueID: \(id.uuidString)"
                        )
                    }
                    Self.logger.critical(
                        "[endAllLiveActivities] Failed to send live activity push notification to \(deviceToken.deviceName) [\(deviceToken.tokenType)]: \(error.localizedDescription)"
                    )
                    try? await DeviceToken.query(on: database)
                        .filter(\.$tokenString == deviceToken.tokenString)
                        .delete()
                }
            }
        } catch {
            Self.logger.critical("Failed to fetch push devices: \(error)")
            assertionFailure()
        }

        do {
            try await DeviceToken
                .query(on: database)
                .filter(\.$activityType == "WindowAttributes")
                .delete()
        } catch {
            Self.logger.critical("Failed to delete old token")
            assertionFailure()
        }
    }
}

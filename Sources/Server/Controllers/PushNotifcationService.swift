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

/// Payload for `content-available` background pushes that tell the client
/// to remove a previously delivered notification matched by `threadIdentifier`.
private struct ClearNotificationPayload: Encodable, Sendable {
    let clearNotificationId: String
}

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

    func sendNotification(title: String, message: String, id: String) async throws {
        try await sendAlert(title: title, message: message, id: id)
    }

    func clearNotification(id: String) async throws {
        let deviceTokens = try await DeviceToken
            .query(on: database)
            .filter(\.$tokenType == "pushNotification")
            .all()

        let payload = ClearNotificationPayload(clearNotificationId: id)
        let notification = APNSBackgroundNotification(
            expiration: .immediately,
            topic: notificationTopic,
            payload: payload
        )

        for deviceToken in deviceTokens {
            do {
                try await apnsClient.sendBackgroundNotification(notification, deviceToken: deviceToken.tokenString)
            } catch {
                Self.logger.critical(
                    "Failed to send clear notification to \(deviceToken.deviceName): \(error.localizedDescription)"
                )
                try? await DeviceToken.query(on: database)
                    .filter(\.$tokenString == deviceToken.tokenString)
                    .delete()
            }
        }
    }

    // MARK: - Private

    private func sendAlert(title: String, message: String, id: String?) async throws {
        let deviceTokens =
            try await DeviceToken
            .query(on: database)
            .filter(\.$tokenType == "pushNotification")
            .all()

        var notification = APNSAlertNotification(
            alert: .init(title: .raw(title), body: .raw(message)),
            expiration: .none,
            priority: .immediately,
            topic: notificationTopic
        )

        if let id {
            notification.collapseID = id
            notification.threadID = id
        }

        for deviceToken in deviceTokens {
            do {
                try await apnsClient.sendAlertNotification(notification, deviceToken: deviceToken.tokenString)
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

    func startOrUpdateLiveActivity<ContentState: Encodable & Sendable>(contentState: ContentState, activityName: String) async {
        Self.logger.debug("Start or update live activity")

        do {
            let allDeviceTokens =
            try await DeviceToken
                .query(on: database)
                .filter(\.$tokenType != "pushNotification")
                .all()

            Self.logger.debug("Found tokens \(allDeviceTokens.count)")

            var deviceTokens: [DeviceToken] = []
            var expiredCount = 0
            for token in allDeviceTokens {
                if token.tokenType == "liveActivityUpdate",
                   let date = token.updatedAt ?? token.createdAt,
                   date < Date().addingTimeInterval(-1 * Duration.hours(4).timeInterval),
                   let tokenId = token.id {

                    // delete liveActivityUpdate tokens that are older than 4 hours
                    try await DeviceToken
                        .query(on: database)
                        .filter(\.$id == tokenId)
                        .delete()
                    expiredCount += 1

                } else {
                    deviceTokens.append(token)
                }
            }
            if expiredCount > 0 {
                Self.logger.info("Deleted \(expiredCount) expired liveActivityUpdate token(s)")
            }

            let deviceMap = Dictionary(grouping: deviceTokens, by: { $0.deviceName })
            Self.logger.info("Processing \(deviceMap.count) device(s) with \(deviceTokens.count) token(s)")
            for tokens in deviceMap.values {
                assert(tokens.count <= 2, "Found device with more than 2 tokens")

                var usedToken: DeviceToken?
                do {
                    if let updateToken = tokens.first(where: {
                        $0.tokenType == "liveActivityUpdate" && $0.activityType == activityName
                    }) {
                        Self.logger.info("Update LiveActivity (on: \(updateToken.deviceName)): \(contentState)")
                        let notification = APNSLiveActivityNotification<ContentState>(
                            expiration: .none,
                            priority: .consideringDevicePower,
                            appID: notificationTopic,
                            contentState: contentState,
                            event: .update,
                            timestamp: Int(Date().timeIntervalSince1970))

                        // if an update token was found, we assume a live activity was found, so we use this token
                        usedToken = updateToken
                        let response = try await apnsClient.sendLiveActivityNotification(notification, deviceToken: updateToken.tokenString)
                        Self.logger.debug("Received send live activity response: \(response)")

                    } else if let startToken = tokens.first(where: {
                        $0.tokenType == "liveActivityStart"
                    }) {
                        Self.logger.info("Starting LiveActivity (on: \(startToken.deviceName)) with attributesType '\(activityName)': \(contentState)")
                        // alert with non-empty title/body is required for push-to-start Live Activities
                        // to be displayed on the device. Omitting or using an empty
                        // APNSAlertNotificationContent() causes iOS to silently drop the notification
                        // and the Live Activity will never appear.
                        let notification = APNSStartLiveActivityNotification<ContentState, ContentState>(
                            expiration: .none,
                            priority: .immediately,
                            appID: notificationTopic,
                            contentState: contentState,
                            timestamp: Int(Date().timeIntervalSince1970),
                            attributes: contentState,
                            attributesType: activityName,
                            alert: APNSAlertNotificationContent(
                                title: .raw("empty"),
                                body: .raw("empty")))

                        // start a new live activity
                        usedToken = startToken
                        try await apnsClient.sendStartLiveActivityNotification(notification, deviceToken: startToken.tokenString)
                        Self.logger.info("Successfully sent start live activity notification to \(startToken.deviceName)")

                        // Delete the start token after successful Push-to-Start to prevent
                        // duplicate Live Activities. Without this, a second call (e.g. another
                        // window opening before the update token roundtrip completes) would find
                        // the same start token and create another activity.
                        //
                        // The token lifecycle ensures recovery:
                        // 1. iOS invalidates the used push-to-start token after delivery
                        // 2. iOS generates a new push-to-start token via pushToStartTokenUpdates
                        // 3. The app re-registers the new token with the server
                        // 4. If the app was not woken (force-quit / iOS budget), the token is
                        //    re-registered when the user next opens the app
                        try? await DeviceToken.query(on: database)
                            .filter(\.$tokenString == startToken.tokenString)
                            .delete()
                    } else {
                        assertionFailure("Should find at least one start token")
                    }
                } catch is CancellationError {
                    // CancellationError is expected when rapid window state changes occur.
                    // The automation task gets cancelled when a newer event arrives, which is
                    // correct behavior - we want to send the most recent state, not stale data.
                    Self.logger.info(
                        "[startOrUpdateLiveActivity] Cancelled for \(usedToken?.deviceName ?? "") (superseded by newer state)"
                    )
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
            let deviceTokens = try await DeviceToken
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
                    let response = try await apnsClient.sendLiveActivityNotification(notification, deviceToken: deviceToken.tokenString)
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
                .filter(\.$activityType == activityType)
                .delete()
        } catch {
            Self.logger.critical("Failed to delete old token")
            assertionFailure()
        }
    }
}

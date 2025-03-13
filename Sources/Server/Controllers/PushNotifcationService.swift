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
    let database: any Database
    let apnsClient: APNSGenericClient
    let notificationTopic: String
    let logger: Logger

    private var windowStateIsOpen: [EntityId: WindowOpenState] = [:]

    init(database: any Database, apnsClient: APNSGenericClient, notificationTopic: String, logger: Logger) {
        self.database = database
        self.apnsClient = apnsClient
        self.notificationTopic = notificationTopic
        self.logger = logger
    }

    func sendNotification(title: String, message: String) async throws {
        let deviceTokens = try await DeviceToken
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
                try await apnsClient.sendAlertNotification(notification, deviceToken: deviceToken.tokenString)
            } catch {
                logger.critical("Failed to send push notification to \(deviceToken.deviceName) [\(deviceToken.tokenType)]: \(error.localizedDescription)")
                try? await DeviceToken.query(on: database)
                    .filter(\.$tokenString == deviceToken.tokenString)
                    .delete()
            }
        }
    }

    /// Set newState to nil, if the window was closed
    func setWindowOpenState(entityId: EntityId, to newState: WindowOpenState?) {
        windowStateIsOpen[entityId] = newState

        let windowStates = windowStateIsOpen.values.sorted(by: { $0.name < $1.name })
        Task {
            if !windowStates.isEmpty {
                await startOrUpdateOpenWindowActivities(with: windowStates)
            } else {
                await endAllOpenWindowActivities()
            }
        }
    }

    private func startOrUpdateOpenWindowActivities(with windowStates: [WindowOpenState]) async {
        assert(!windowStates.isEmpty, "Use 'endAllOpenWindowActivities' when no window is opened")
        logger.debug("Start or update open window activity")

        let states = windowStates.map { windowState in
            WindowOpenContentState.WindowState(name: windowState.name,
                                               opened: windowState.opened,
                                               maxOpenDuration: windowState.maxOpenDuration)
        }
        let contentState = WindowOpenContentState(windowStates: states)

        do {
            let deviceTokens = try await DeviceToken
                .query(on: database)
                .filter(\.$tokenType != "pushNotification")
                .all()

            logger.debug("Found tokens \(deviceTokens.count)")

            let deviceMap = Dictionary(grouping: deviceTokens, by: { $0.deviceName })
            for tokens in deviceMap.values {
                assert(tokens.count <= 2, "Found device with more than 2 tokens")
                if let updateToken = tokens.first(where: { $0.tokenType == "liveActivityUpdate" }) {
                    logger.info("Update LiveActivity (on: \(updateToken.deviceName)): \(contentState)")
                    let notification = APNSLiveActivityNotification<WindowOpenContentState>(expiration: .immediately,
                                                                                            priority: .immediately,
                                                                                            appID: notificationTopic,
                                                                                            contentState: contentState,
                                                                                            event: .update,
                                                                                            timestamp: Int(Date().timeIntervalSince1970))

                    // if an update token was found, we assume a live activity was found, so we use this token
                    try await sendLiveActivity(notification, to: [updateToken])

                } else if let startToken = tokens.first(where: { $0.tokenType == "liveActivityStart" }) {
                    logger.info("Starting LiveActivity (on: \(startToken.deviceName)): \(contentState)")
                    let notification = APNSStartLiveActivityNotification<WindowOpenContentState, WindowOpenContentState>(
                        expiration: APNSNotificationExpiration.immediately,
                        priority: APNSPriority.immediately,
                        appID: notificationTopic,
                        contentState: contentState,
                        timestamp: Int(Date().timeIntervalSince1970),
                        dismissalDate: APNSLiveActivityDismissalDate.none,
                        apnsID: UUID(),
                        attributes: contentState,
                        attributesType: "WindowOpenAttributes",
                        alert: APNSAlertNotificationContent(title: .raw("empty"),
                                                            body: .raw("empty")))

                    // start a new live activity
                    try await apnsClient.sendStartLiveActivityNotification(notification, deviceToken: startToken.tokenString)
                } else {
                    assertionFailure("Should find at least one start token")
                }
            }

        } catch {
            logger.critical("Failed to fetch push devices in startOrUpdateOpenWindowActivities: \(error)")
            assertionFailure()
        }
    }

    private func endAllOpenWindowActivities() async {
        do {
            let deviceTokens = try await DeviceToken
                .query(on: database)
                .filter(\.$activityType == "WindowOpenAttributes")
                .all()

            let contentState = WindowOpenContentState(windowStates: [])
            let notification = APNSLiveActivityNotification<WindowOpenContentState>(expiration: .immediately,
                                                                                    priority: .immediately,
                                                                                    appID: notificationTopic,
                                                                                    contentState: contentState,
                                                                                    event: .end,
                                                                                    timestamp: Int(Date().timeIntervalSince1970),
                                                                                    dismissalDate: .date(Date()))

            try await sendLiveActivity(notification, to: deviceTokens)
        } catch {
            logger.critical("Failed to fetch push devices: \(error)")
            assertionFailure()
        }

        do {
            try await DeviceToken
                .query(on: database)
                .filter(\.$activityType == "WindowOpenAttributes")
                .delete()
        } catch {
            logger.critical("Failed to delete old token")
            assertionFailure()
        }
    }

    private func sendLiveActivity<ContentState: Encodable & Sendable>(_ notification: APNSLiveActivityNotification<ContentState>, to deviceTokens: [DeviceToken]) async throws {
        for deviceToken in deviceTokens {
            do {
                let response = try await apnsClient.sendLiveActivityNotification(notification, deviceToken: deviceToken.tokenString)
                logger.debug("Received send live activity response: \(response)")
            } catch {
                logger.critical("Failed to send live activity push notification to \(deviceToken.deviceName) [\(deviceToken.tokenType)]: \(error.localizedDescription)")
                try? await DeviceToken.query(on: database)
                    .filter(\.$tokenString == deviceToken.tokenString)
                    .delete()
            }
        }
    }
}

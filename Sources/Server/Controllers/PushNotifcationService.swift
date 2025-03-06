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
import APNSCore

actor PushNotifcationService: NotificationSender {
    let database: any Database
    let apnsClient: APNSGenericClient
    let notificationTopic: String
    let logger: Logger
    
    struct WindowOpenState: Hashable, Encodable {
        let name: String
        let opened: Date
        let maxOpenDuration: TimeInterval
    }
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
                logger.critical("Failed to send push notification to \(deviceToken.tokenString): \(error.localizedDescription)")
//                try? await DeviceToken.query(on: database)
//                    .filter(\.$tokenString == deviceToken.tokenString)
//                    .delete()
            }
        }
    }
    
    /// Set newState to nil, if the window was closed
    func update(entityId: EntityId, to newState: WindowOpenState?) {
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
        
        do {
            let deviceTokens = try await DeviceToken
                .query(on: database)
                .filter(\.$tokenType != "pushNotification")
                .all()
            
            let deviceMap = Dictionary(grouping: deviceTokens, by: { $0.deviceName })
            for tokens in deviceMap.values {
                assert(tokens.count <= 2, "Found device with more than 2 tokens")
                if let updateToken = tokens.first(where: { $0.tokenType == "liveActivityUpdate" }) {
                    // TODO: send update
                    
                } else if let startToken = tokens.first(where: { $0.tokenType == "liveActivityStart" }) {
                    // TODO: send start

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
    }
    

    
    private func sendLiveActivity<ContentState: Encodable & Sendable>(_ notification:  APNSLiveActivityNotification<ContentState>, to deviceTokens: [DeviceToken]) async throws {
        for deviceToken in deviceTokens {
            do {
                let response = try await apnsClient.sendLiveActivityNotification(notification, deviceToken: deviceToken.tokenString)
                logger.debug("Received send live activity response: \(response)")
            } catch {
                logger.critical("Failed to send push notification to \(deviceToken.tokenString): \(error.localizedDescription)")
//                try? await DeviceToken.query(on: database)
//                    .filter(\.$tokenString == deviceToken.tokenString)
//                    .delete()
            }
        }
    }
}

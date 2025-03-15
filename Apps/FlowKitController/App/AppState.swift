//
//  AppState.swift
//  FlowKit Controller
//
//  Created by Julian Kahnert on 06.03.25.
//

import ActivityKit
import HAModels
import Logging
import LoggingOSLog
import SwiftUI

@MainActor
@Observable
final class AppState {
    private let logger = Logger(label: "AppState")

    // state if the WindowOpenActivity in this app
    var activityViewState: WindowContentState?

    var flowKitClient: FlowKitClient? {
        guard let url = UserDefaults.standard.url(forKey: FlowKitClient.userDefaultsKey) else {
            logger.critical("Failed to get client URL")
            assertionFailure()
            return nil
        }

        return FlowKitClient(url: url)
    }

    init() {
        LoggingSystem.bootstrap { label in
            let handlers: [LogHandler] = [
                LoggingOSLog(label: label)
            ]
            var mpxHandler = MultiplexLogHandler(handlers)
            mpxHandler.logLevel = .debug
            return MultiplexLogHandler(handlers)
        }

        Task {
            await observeLiveActivityStartTokens()
        }

        Task {
            let activity = await Activity<WindowAttributes>.activityUpdates.makeAsyncIterator().next()
            guard let activity else {
                logger.error("FAILED to get pushToken")
                return
            }
            observeActivity(activity: activity)
        }

        Task {
            for activity in Activity<WindowAttributes>.activities {
                logger.info("Found running activity \(activity)")
                observeActivity(activity: activity)
            }
        }
    }

    // this should be done by the server later
    func startLiveActivity() {
        Task {
            do {
                let window1 = Date()
                let initialState = WindowAttributes.ContentState(windowStates: [
                    .init(name: "window1", opened: window1, maxOpenDuration: 30)
                ])

                let activity = try Activity<WindowAttributes>.request(
                    attributes: WindowAttributes(),
                    content: .init(state: initialState, staleDate: nil),
                    pushType: .token
                )

                try await Task.sleep(for: .seconds(2))
                let window2 = Date()
                await activity.update(.init(state: .init(windowStates: [
                    .init(name: "window1", opened: window1, maxOpenDuration: 30),
                    .init(name: "window2", opened: window2, maxOpenDuration: 30)
                ]), staleDate: nil))

                try await Task.sleep(for: .seconds(2))
                await activity.update(.init(state: .init(windowStates: [
                    .init(name: "window2", opened: window2, maxOpenDuration: 30)
                ]), staleDate: nil))

                try await Task.sleep(for: .seconds(2))
                await activity.end(.init(state: .init(windowStates: []), staleDate: Date()), dismissalPolicy: .after(Date().addingTimeInterval(2)))
            } catch {
                logger.critical("Failed to run live activity: \(error)")
            }
        }
    }

    func fetchWindowState() async {
        guard let flowKitClient else { return }
        do {
            let states = try await flowKitClient.getWindowStates()
            self.activityViewState = states.isEmpty ? nil : .init(windowStates: states)
        } catch {
            logger.critical("Failed to fetch window states: \(error)")
            assertionFailure()
        }
    }

    func observeLiveActivityStartTokens() async {
        for await pushToken in Activity<WindowAttributes>.pushToStartTokenUpdates {
            await self.send(pushToken: pushToken, ofType: .liveActivityStart)
        }
    }

    func observeActivity(activity: Activity<WindowAttributes>) {
        logger.info("observeActivity activity \(activity.id)")
        Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    for await contentState in activity.contentUpdates {
                        self.activityViewState = contentState.state.windowStates.isEmpty ? nil : contentState.state
                    }
                }

                group.addTask { @MainActor in
                    for await pushToken in activity.pushTokenUpdates {
                        await self.send(pushToken: pushToken, ofType: .liveActivityUpdate(activityName: String(describing: activity.self)))
                    }
                }
            }
        }
    }

    func send(pushToken: Data, ofType type: PushTokenType) async {
        let pushTokenString = pushToken.hexadecimalString
        logger.debug("New push token (\(type)): \(pushTokenString)")

        #if canImport(UIKit)
        let deviceName = UIDevice.current.name
        #else
        let deviceName = Host.current.localizedName(for: .current, locale: .current)
        #endif

//        let frequentUpdateEnabled = ActivityAuthorizationInfo().frequentPushesEnabled
        logger.info("Sending (\(type)) of \(deviceName)")

        do {
            typealias PushTokenTypeDto = Components.Schemas.PushDevice.TokenTypePayload
            let tokenTypeDto: PushTokenTypeDto
            var activityNameDto: String?
            switch type {
            case .pushNotification:
                tokenTypeDto = .pushNotification
            case .liveActivityStart:
                tokenTypeDto = .liveActivityStart
            case .liveActivityUpdate(let activityName):
                tokenTypeDto = .liveActivityUpdate
                activityNameDto = activityName
            }

            try await flowKitClient?.register(deviceName: deviceName,
                                              tokenString: pushTokenString,
                                              tokenType: tokenTypeDto,
                                              activityType: activityNameDto)
        } catch {
            logger.critical("""
            Failed to send push token to server
            ------------------------
            \(String(describing: error))
            """)
        }
    }
}

enum PushTokenType {
    case pushNotification
    case liveActivityStart
    case liveActivityUpdate(activityName: String)
}

private extension Data {
    var hexadecimalString: String {
        self.reduce("") {
            $0 + String(format: "%02x", $1)
        }
    }
}

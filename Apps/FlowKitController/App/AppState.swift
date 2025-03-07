//
//  AppState.swift
//  FlowKit Controller
//
//  Created by Julian Kahnert on 06.03.25.
//

import ActivityKit
import SwiftUI
import Logging
import LoggingOSLog

@MainActor
@Observable
final class AppState {
    private let logger = Logger(label: "AppState")
    
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
            let activity = await Activity<WindowOpenAttributes>.activityUpdates.makeAsyncIterator().next()
            guard let activity else {
                logger.error("FAILED to get pushToken")
                return
            }
            observeActivity(activity: activity)
//            logger.info("didReceiveRemoteNotification activity \(activity?.id)")
//
//                await send(pushToken: token, ofType: .liveActivityUpdate)
        }
        
        Task {
            for activity in Activity<WindowOpenAttributes>.activities {
                logger.info("Found running activity \(activity)")
                observeActivity(activity: activity)
            }
        }
    }
//    @Published var activityViewState: WindowOpenAttributes.ContentState?
    
    // this should be done by the server later
    func startLiveActivity() {
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            do {
                let date = Date()
                let initialState = WindowOpenAttributes.ContentState(windowStates: [
                    .init(name: "window1", opened: date, maxOpenDuration: 60.0 * 3),
                    .init(name: "window2", opened: date.addingTimeInterval(-1 * 60), maxOpenDuration: 60.0 * 3)
                ])
                
                let activity = try Activity<WindowOpenAttributes>.request(
                    attributes: WindowOpenAttributes(),
                    content: .init(state: initialState, staleDate: nil),
                    pushType: .token
                )
                
//                self.activityViewState = activity.content.state
            } catch {
                let errorMessage = """
                    Couldn't start activity
                    ------------------------
                    \(String(describing: error))
                    """
                
                assertionFailure(errorMessage)
            }
        }
    }
    
    func observeLiveActivityStartTokens() async {
        for await pushToken in Activity<WindowOpenAttributes>.pushToStartTokenUpdates {
            await self.send(pushToken: pushToken, ofType: .liveActivityStart)
            Date().timeIntervalSinceReferenceDate
            
        }
    }
    
    func observeActivity(activity: Activity<WindowOpenAttributes>) {
        Task {
            await withTaskGroup(of: Void.self) { group in
//                group.addTask { @MainActor in
//                    for await contentState in activity.contentUpdates {
////                        self.activityViewState = contentState.state
//                    }
//                }
                
                group.addTask { @MainActor in
                    for await pushToken in activity.pushTokenUpdates {
                        await self.send(pushToken: pushToken, ofType: .liveActivityUpdate)
                    }
                }
            }
        }
    }

    func send(pushToken: Data, ofType type: PushTokenType) async {
        let pushTokenString = pushToken.hexadecimalString
        logger.debug("New push token (\(type.rawValue)): \(pushTokenString)")
        
        #if canImport(UIKit)
        let deviceName = UIDevice.current.name
        #else
        let deviceName = Host.current.localizedName(for: .current, locale: .current)
        #endif

//        let frequentUpdateEnabled = ActivityAuthorizationInfo().frequentPushesEnabled
        
        logger.info("Sending (\(type.rawValue)) of [\(deviceName)]: \(pushTokenString)")

        do {
            guard let url = UserDefaults.standard.url(forKey: FlowKitClient.userDefaultsKey) else {
                logger.critical("Failed to get client URL")
//                assertionFailure()
                return
            }
            let client = FlowKitClient(url: url)
            
            // TODO: implement sending push token
//            try await client.register(pushDeviceToken: tokenString)
        } catch {
            logger.critical("""
            Failed to send push token to server
            ------------------------
            \(String(describing: error))
            """)
        }
    }
}

enum PushTokenType: String {
    case pushNotification
    case liveActivityStart
    case liveActivityUpdate
}

private extension Data {
    var hexadecimalString: String {
        self.reduce("") {
            $0 + String(format: "%02x", $1)
        }
    }
}

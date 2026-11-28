//
//  PushToken.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 18.11.25.
//

public struct PushToken: Sendable {
    public enum TokenType: Sendable {
        case pushNotification
        /// The push-to-start token of one activity type (`ActivityAttributes` name); each type has its own.
        case liveActivityStart(activityName: String)
        case liveActivityUpdate(activityName: String)

        public var activityType: String? {
            switch self {
            case .pushNotification:
                return nil
            case .liveActivityStart(activityName: let name), .liveActivityUpdate(activityName: let name):
                return name
            }
        }
    }
    public let deviceName: String
    public let tokenString: String
    public let type: TokenType

    public init(deviceName: String, tokenString: String, type: TokenType) {
        self.deviceName = deviceName
        self.tokenString = tokenString
        self.type = type
    }
}

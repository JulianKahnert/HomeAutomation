//
//  PushToken.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 18.11.25.
//

public struct PushToken: Sendable {
    public enum TokenType: Sendable {
        case pushNotification
        case liveActivityStart
        case liveActivityUpdate(activityName: String)

        public var activityType: String? {
            switch self {
            case .pushNotification, .liveActivityStart:
                return nil
            case .liveActivityUpdate(activityName: let name):
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

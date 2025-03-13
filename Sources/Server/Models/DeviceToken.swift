//
//  PushDevice.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 04.03.25.
//

import Fluent
import Vapor

final class DeviceToken: Model, Content, @unchecked Sendable {
    static let schema = "deviceToken"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "tokenString")
    var tokenString: String

    @Field(key: "deviceName")
    var deviceName: String

    @Field(key: "tokenType")
    var tokenType: String

    @Field(key: "activityType")
    var activityType: String?

    @Timestamp(key: "createdAt", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updatedAt", on: .update)
    var updatedAt: Date?

    init() { }

    init(deviceName: String, tokenString: String, tokenType: String, activityType: String?) {
        self.deviceName = deviceName
        self.tokenString = tokenString
        self.tokenType = tokenType
        self.activityType = activityType
    }
}

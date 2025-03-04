//
//  PushDevice.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 04.03.25.
//

import Fluent
import Vapor

final class PushDevice: Model, Content, @unchecked Sendable {
    static let schema = "pushDevices"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "deviceToken")
    var deviceToken: String

    @Timestamp(key: "createdAt", on: .create)
    var createdAt: Date?

    @Timestamp(key: "updatedAt", on: .update)
    var updatedAt: Date?

    init() { }

    init(id: UUID? = nil, deviceToken: String) {
        self.id = id
        self.deviceToken = deviceToken
    }
}

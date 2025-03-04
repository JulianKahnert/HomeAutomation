//
//  NotificationSender.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 23.07.24.
//

import Foundation

public protocol NotificationSender: Sendable {
    func sendNotification(title: String, message: String) async throws
}

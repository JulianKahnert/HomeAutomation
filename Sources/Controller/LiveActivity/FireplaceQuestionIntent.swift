//
//  FireplaceQuestionIntent.swift
//  ControllerFeatures
//

import AppIntents
import Dependencies
import Foundation
import Logging

/// The App Intents of the Controller module, for the `AppIntentsPackage` of the app and the widget extension.
public struct ControllerAppIntents: AppIntentsPackage {}

#if os(iOS)
private let logger = Logger(label: "FireplaceQuestionIntent")

/// The buttons "Ja" and "Nein" of the fireplace question. A Live Activity intent runs in the app's process, which
/// the system starts in the background when needed, so the app's server settings apply.
public struct AnswerFireplaceQuestionIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Kamin-Frage beantworten"
    public static let isDiscoverable = false

    @Parameter(title: "Kamin noch an")
    public var stillOn: Bool

    public init() {}

    public init(stillOn: Bool) {
        self.stillOn = stillOn
    }

    public func perform() async throws -> some IntentResult {
        @Dependency(\.serverClient) var serverClient
        @Dependency(\.liveActivity) var liveActivity
        logger.info("Answering the fireplace question", metadata: ["stillOn": "\(stillOn)"])
        do {
            _ = try await serverClient.answerFireplaceQuestion(stillOn)
        } catch {
            // The question stays, so the resident can answer again.
            logger.error("Failed to answer the fireplace question", metadata: ["error": "\(error)"])
            throw error
        }
        // The server ends it everywhere; ending it here as well removes it before that push arrives.
        await liveActivity.endFireplaceQuestion()
        return .result()
    }
}
#endif

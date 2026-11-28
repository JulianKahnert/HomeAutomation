//
//  FlowKit_Controller_WidgetExtensionBundle.swift
//  FlowKit Controller WidgetExtension
//
//  Created by Julian Kahnert on 06.03.25.
//

// swiftlint:disable type_name

import AppIntents
import Controller
import SwiftUI
import WidgetKit

@main
struct FlowKit_Controller_WidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        WindowOpenPushConfiguration()
        FireplaceQuestionConfiguration()
    }
}

/// The intents of the Controller module (the answers of the fireplace question) for this extension's metadata.
struct WidgetExtensionAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [ControllerAppIntents.self] }
}

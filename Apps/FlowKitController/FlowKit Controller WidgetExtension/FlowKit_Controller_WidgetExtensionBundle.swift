//
//  FlowKit_Controller_WidgetExtensionBundle.swift
//  FlowKit Controller WidgetExtension
//
//  Created by Julian Kahnert on 06.03.25.
//

import SwiftUI
import WidgetKit

@main
struct FlowKit_Controller_WidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        FlowKit_Controller_WidgetExtension()
        #if os(iOS)
        WindowOpenPushConfiguration()
        #endif
    }
}

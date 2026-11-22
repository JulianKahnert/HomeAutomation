//
//  HeatingFireplace.swift
//  ControllerFeatures
//
//  The fireplace switch of the Heizung tab: the toolbar button (variant H-D of the fireplace prototype),
//  the subtitle under the title and the notification category of the push "Kamin an?"
//

import Foundation
import HAModels
import SwiftUI
import UserNotifications

extension HeatingFormat {
    /// "Kamin an · endet in 1 h" while the fireplace burns, `nil` while it is off.
    static func fireplaceHint(_ state: FireplaceState, now: Date) -> String? {
        guard state.isOn, let end = state.endsAt else { return nil }
        let hours = end.timeIntervalSince(now) / 3_600
        if hours <= 0 { return "Kamin an · endet gleich" }
        if hours < 1 { return "Kamin an · endet in < 1 h" }
        return "Kamin an · endet in \(Int(hours.rounded())) h"
    }
}

/// The toolbar item: a flame, filled and orange while the fireplace is on.
struct FireplaceToolbarButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Kamin", systemImage: isOn ? "flame.fill" : "flame")
                .foregroundStyle(isOn ? Color.orange : Color.primary)
        }
        .accessibilityValue(isOn ? "an" : "aus")
    }
}

extension View {
    /// The line under the navigation title; where the system has no subtitle (iOS before 26) it is left out.
    @ViewBuilder
    func heatingSubtitle(_ text: String) -> some View {
        #if os(iOS)
        if #available(iOS 26, *) {
            navigationSubtitle(text)
        } else {
            self
        }
        #else
        navigationSubtitle(text)
        #endif
    }
}

/// The push "Kamin an?" and its action. The server sends the category (`Fireplace.notificationCategory`);
/// the action switches the fireplace on through the server without opening the app.
enum FireplaceNotification {
    static var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: Fireplace.notificationCategory,
            actions: [UNNotificationAction(identifier: Fireplace.switchOnActionId, title: "Heizkörper ausschalten", options: [])],
            intentIdentifiers: [],
            options: []
        )
    }

    /// What the action `actionIdentifier` of a delivered notification asks for; `nil` for any other action
    /// (tapping the notification, dismissing it).
    static func requestedState(forAction actionIdentifier: String) -> Bool? {
        actionIdentifier == Fireplace.switchOnActionId ? true : nil
    }
}

#Preview("Kamin-Knopf") {
    HStack(spacing: 24) {
        FireplaceToolbarButton(isOn: false) {}
        FireplaceToolbarButton(isOn: true) {}
    }
    .padding(24)
}

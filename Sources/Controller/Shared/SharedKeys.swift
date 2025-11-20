//
//  SharedKeys.swift
//  ControllerFeatures
//
//  Shared state keys for TCA features
//

import ComposableArchitecture
import Foundation
import HAModels
import Sharing

// MARK: - AppStorage-backed (UserDefaults)

extension SharedKey where Self == AppStorageKey<URL>.Default {
    /// Server URL for the FlowKit backend
    static var serverURL: Self {
        let defaultValue = URL(string: "http://localhost:8080/")!
        return Self[.appStorage("serverURL", store: .standard), default: defaultValue]
    }
}

extension SharedKey where Self == AppStorageKey<Bool>.Default {
    /// Whether Live Activities are enabled
    static var liveActivitiesEnabled: Self {
        Self[.appStorage("liveActivitiesEnabled", store: .standard), default: true]
    }
}

// MARK: - In-Memory (volatile state)

 extension SharedKey where Self == InMemoryKey<IdentifiedArrayOf<AutomationInfo>> {
    /// List of automations from the server
    static var automations: Self {
        inMemory("automations")
    }
 }

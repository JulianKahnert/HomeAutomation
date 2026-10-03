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

// MARK: - Keychain-backed (survives app reinstalls)

extension SharedKey where Self == KeychainKey<URL>.Default {
    /// Server URL for the FlowKit backend
    static var serverURL: Self {
        let defaultValue = URL(string: "http://localhost:8080")!
        return Self[.keychain("serverURL"), default: defaultValue]
    }
}

extension SharedKey where Self == KeychainKey<String>.Default {
    /// Authentication token for the FlowKit backend
    static var authToken: Self {
        Self[.keychain("authToken"), default: ""]
    }
}

extension SharedKey where Self == AppStorageKey<Bool>.Default {
    /// Whether Live Activities are enabled
    static var liveActivitiesEnabled: Self {
        Self[.appStorage("liveActivitiesEnabled", store: .standard), default: true]
    }
}

extension SharedKey where Self == AppStorageKey<AutomationsFeature.Grouping>.Default {
    static var automationGrouping: Self {
        Self[.appStorage("automationGrouping", store: .standard), default: .status]
    }
}

extension SharedKey where Self == AppStorageKey<Location?>.Default {
    /// Server location from `GET /config`, for night bands in charts
    static var serverLocation: Self {
        Self[.appStorage("serverLocation", store: .standard), default: nil]
    }
}

// MARK: - In-Memory (volatile state)

 extension SharedKey where Self == InMemoryKey<IdentifiedArrayOf<AutomationInfo>> {
    /// List of automations from the server
    static var automations: Self {
        inMemory("automations")
    }
 }

//
//  SharedKeys.swift
//  ControllerFeatures
//
//  Shared state keys for TCA features
//

import Foundation
import HAModels
import Sharing

// MARK: - AppStorage-backed (UserDefaults)

public extension SharedKey where Self == AppStorageKey<URL>.Default {
    /// Server URL for the FlowKit backend
    static var serverURL: Self {
        let defaultValue = URL(string: "http://localhost:8080/")!
        return Self[.appStorage("serverURL", store: .standard), default: defaultValue]
    }
}

public extension SharedKey where Self == AppStorageKey<Bool>.Default {
    /// Whether Live Activities are enabled
    static var liveActivitiesEnabled: Self {
        Self[.appStorage("liveActivitiesEnabled", store: .standard), default: true]
    }
}

// MARK: - In-Memory (volatile state)

public extension SharedKey where Self == InMemoryKey<[Automation]> {
    /// List of automations from the server
    static var automations: Self {
        inMemory("automations")
    }
}

public extension SharedKey where Self == InMemoryKey<[ActionLogItem]> {
    /// List of action log items
    static var actions: Self {
        inMemory("actions")
    }
}

public extension SharedKey where Self == InMemoryKey<Int?> {
    /// Index of currently selected automation
    static var selectedAutomationIndex: Self {
        inMemory("selectedAutomationIndex")
    }
}

public extension SharedKey where Self == InMemoryKey<Bool> {
    /// Global loading state
    static var isLoading: Self {
        inMemory("isLoading")
    }
}

public extension SharedKey where Self == InMemoryKey<WindowContentState?> {
    /// Current window content state for Live Activities
    static var windowContentState: Self {
        inMemory("windowContentState")
    }
}

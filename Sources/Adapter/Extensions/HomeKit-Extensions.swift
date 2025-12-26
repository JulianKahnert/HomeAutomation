//
//  Extensions.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 21.07.24.
//

#if canImport(HomeKit)
import HAModels
import HomeKit
import Logging

extension HMAction {
    var characteristic: HMCharacteristic? {
        value(forKey: "characteristic") as? HMCharacteristic
    }
}

extension HMAccessory {
    var home: HMHome? {
        value(forKey: "home") as? HMHome
    }
}

extension HMActionSet {
    var home: HMHome? {
        value(forKey: "home") as? HMHome
    }
}
#endif

//
//  Data.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 18.11.25.
//

import Foundation

public extension Data {
    var hexadecimalString: String {
        self.reduce("") {
            $0 + String(format: "%02x", $1)
        }
    }
}

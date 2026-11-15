//
//  DebugLoggingTests.swift
//  HomeAutomationKit
//

import Foundation
import Logging
@testable import Shared
import Testing

struct DebugLoggingTests {
    @Test("The environment variable switches debug logging", arguments: [
        ("1", true), ("true", true), ("YES", true), (" on ", true),
        ("0", false), ("false", false), ("", false), ("debug", false)
    ])
    func environment(value: String, expected: Bool) {
        #expect(DebugLogging.isEnabled(environment: [DebugLogging.key: value]) == expected)
    }

    @Test("Off by default")
    func offByDefault() {
        #expect(!DebugLogging.isEnabled(environment: [:]))
    }

    @Test("The user setting switches it when the environment does not, the environment wins")
    func userSetting() {
        #expect(!DebugLogging.isEnabled(environment: [:], userSetting: false))
        #expect(DebugLogging.isEnabled(environment: [:], userSetting: true))
        #expect(!DebugLogging.isEnabled(environment: [DebugLogging.key: "0"], userSetting: true))
        #expect(DebugLogging.isEnabled(environment: [DebugLogging.key: "1"], userSetting: false))
    }

    @Test("The switch lowers the level to debug and keeps trace", arguments: [
        (Logger.Level.notice, true, Logger.Level.debug),
        (.info, true, .debug),
        (.trace, true, .trace),
        (.notice, false, .notice),
        (.info, false, .info)
    ])
    func level(level: Logger.Level, enabled: Bool, expected: Logger.Level) {
        #expect(DebugLogging.level(level, enabled: enabled) == expected)
    }
}

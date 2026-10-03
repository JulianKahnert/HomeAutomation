//
//  AutomationInfoDisplayTests.swift
//  ControllerTests
//

@testable import Controller
import Foundation
import HAModels
import Testing

@Suite("AutomationInfo display")
struct AutomationInfoDisplayTests {
    @Test("known types get a label and symbol, unknown and missing types fall back")
    func typeLabels() {
        let motion = AutomationInfo(name: "a", isActive: true, isRunning: false, type: "MotionAtNight")
        #expect(motion.typeLabel == "Motion")
        #expect(motion.systemImage == "figure.walk")
        #expect(motion.triggerDescription == "Motion sensor")

        let unknown = AutomationInfo(name: "b", isActive: true, isRunning: false, type: "Something")
        #expect(unknown.typeLabel == "Other")
        #expect(unknown.systemImage == "gearshape")
        #expect(unknown.triggerDescription == "Unknown trigger")

        let oldServer = AutomationInfo(name: "c", isActive: true, isRunning: false)
        #expect(oldServer.typeLabel == "Other")
    }

    @Test("subtitle shows the trigger configuration until the first run, then the last run")
    func subtitleFollowsLastRun() {
        var info = AutomationInfo(name: "a", isActive: true, isRunning: false, type: "MotionAtNight")
        #expect(info.subtitle == "Motion sensor")

        info.lastRun = AutomationRun(
            automationName: "a",
            startedAt: Date(timeIntervalSince1970: 0),
            trigger: AutomationTrigger(kind: .sunset, entityId: nil, summary: "Sunset"),
            outcome: .completed
        )
        #expect(info.subtitle.hasPrefix("last "))
        #expect(info.subtitle.hasSuffix(" · Sunset"))
    }
}

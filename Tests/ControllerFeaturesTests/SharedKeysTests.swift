//
//  SharedKeysTests.swift
//  ControllerFeaturesTests
//
//  Tests for shared state keys
//

@testable import ControllerFeatures
import Sharing
import Testing

@Suite("Shared Keys Tests")
struct SharedKeysTests {

    @Test("Server URL has correct default value")
    func testServerURLDefault() async {
        let url = Shared(.serverURL).wrappedValue
        #expect(url.absoluteString == "http://localhost:8080/")
    }

    @Test("Live Activities enabled default value")
    func testLiveActivitiesEnabledDefault() async {
        let enabled = Shared(.liveActivitiesEnabled).wrappedValue
        #expect(enabled == true)
    }
}

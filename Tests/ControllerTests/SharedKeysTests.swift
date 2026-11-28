//
//  SharedKeysTests.swift
//  ControllerFeaturesTests
//
//  Tests for shared state keys
//

@testable import Controller
import Dependencies
import Foundation
import Sharing
import Testing

@Suite("Shared Keys Tests")
struct SharedKeysTests {

    @Test("Server URL has correct default value")
    func testServerURLDefault() async {
        let url = Shared(.serverURL).wrappedValue
        #expect(url.absoluteString == "http://localhost:8080")
    }

    @Test("Live Activities enabled default value")
    func testLiveActivitiesEnabledDefault() async {
        // A store of its own: other tests flip this key, and `UserDefaults.standard` is shared by parallel tests.
        let enabled = withDependencies {
            $0.defaultAppStorage = UserDefaults(suiteName: "SharedKeysTests-\(UUID().uuidString)") ?? .standard
        } operation: {
            Shared(.liveActivitiesEnabled).wrappedValue
        }
        #expect(enabled == true)
    }
}

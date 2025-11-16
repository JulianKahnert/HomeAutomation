//
//  FlowKitClientDependencyTests.swift
//  ControllerFeaturesTests
//
//  Tests for FlowKitClient dependency
//

@testable import ControllerFeatures
import Dependencies
import Foundation
import Testing

@Suite("FlowKitClient Dependency Tests")
struct FlowKitClientDependencyTests {

    @Test("Test value returns empty arrays")
    func testTestValue() async throws {
        try await withDependencies {
            $0.flowKitClient = .testValue
        } operation: {
            @Dependency(\.flowKitClient) var client

            let automations = try await client.getAutomations()
            #expect(automations.isEmpty)

            let actions = try await client.getActions(10)
            #expect(actions.isEmpty)

            let windowStates = try await client.getWindowStates()
            #expect(windowStates.isEmpty)
        }
    }

    @Test("Preview value returns mock data")
    func testPreviewValue() async throws {
        try await withDependencies {
            $0.flowKitClient = .previewValue
        } operation: {
            @Dependency(\.flowKitClient) var client

            let automations = try await client.getAutomations()
            #expect(automations.count == 3)
            #expect(automations[0].name == "Morning Routine")
            #expect(automations[0].isActive == true)
            #expect(automations[0].isRunning == true)

            let actions = try await client.getActions(10)
            #expect(actions.count == 1)
            #expect(actions[0].actionName == "Turn On")

            let windowStates = try await client.getWindowStates()
            #expect(windowStates.count == 1)
            #expect(windowStates[0].name == "Living Room Window")
        }
    }

    @Test("Activate/deactivate/stop operations don't throw")
    func testOperations() async throws {
        try await withDependencies {
            $0.flowKitClient = .previewValue
        } operation: {
            @Dependency(\.flowKitClient) var client

            try await client.activate("Morning Routine")
            try await client.deactivate("Morning Routine")
            try await client.stop("Morning Routine")
            try await client.clearActions()
        }
    }

    @Test("Register device doesn't throw")
    func testRegisterDevice() async throws {
        try await withDependencies {
            $0.flowKitClient = .previewValue
        } operation: {
            @Dependency(\.flowKitClient) var client

            try await client.registerDevice(
                "Test Device",
                "abc123",
                .apns,
                "window_state"
            )
        }
    }
}

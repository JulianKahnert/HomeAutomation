//
//  PushTokenDeviceNameTests.swift
//  ControllerTests
//

@testable import Controller
import Foundation
import HAModels
import Testing

@Suite("PushToken device name")
struct PushTokenDeviceNameTests {
    @Test("two devices with the same generic name get different names")
    func sameNameDiffersByVendorId() throws {
        let first = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let second = try #require(UUID(uuidString: "AAAAAAAA-2222-3333-4444-555555555555"))

        #expect(PushToken.deviceName(name: "iPhone", vendorId: first) == "iPhone (11111111)")
        #expect(PushToken.deviceName(name: "iPhone", vendorId: second) != PushToken.deviceName(name: "iPhone", vendorId: first))
    }

    @Test("without vendor id the plain name is used")
    func fallsBackToName() {
        #expect(PushToken.deviceName(name: "iPhone", vendorId: nil) == "iPhone")
    }
}

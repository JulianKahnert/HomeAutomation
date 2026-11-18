//
//  SecurityHardeningTests.swift
//  HomeAutomation
//

@testable import Server
import XCTest

final class SecurityHardeningTests: XCTestCase {

    // MARK: - Constant-time token comparison

    func testConstantTimeEqualsAcceptsIdenticalTokens() {
        XCTAssertTrue(TokenAuthenticationMiddleware.constantTimeEquals("6TnhdoB/abc+123=", "6TnhdoB/abc+123="))
        XCTAssertTrue(TokenAuthenticationMiddleware.constantTimeEquals("", ""))
    }

    func testConstantTimeEqualsRejectsDifferences() {
        XCTAssertFalse(TokenAuthenticationMiddleware.constantTimeEquals("abcdef", "Abcdef")) // first byte
        XCTAssertFalse(TokenAuthenticationMiddleware.constantTimeEquals("abcdef", "abcdeF")) // last byte
        XCTAssertFalse(TokenAuthenticationMiddleware.constantTimeEquals("abcdef", "abcde"))  // prefix
        XCTAssertFalse(TokenAuthenticationMiddleware.constantTimeEquals("abcde", "abcdef"))  // longer guess
        XCTAssertFalse(TokenAuthenticationMiddleware.constantTimeEquals("", "a"))
        XCTAssertFalse(TokenAuthenticationMiddleware.constantTimeEquals("a", ""))
    }

    func testConstantTimeEqualsHandlesMultiByteCharacters() {
        XCTAssertTrue(TokenAuthenticationMiddleware.constantTimeEquals("tökén", "tökén"))
        XCTAssertFalse(TokenAuthenticationMiddleware.constantTimeEquals("tökén", "token"))
    }

    // MARK: - Limit clamping

    func testClampedLimitUsesDefaultWhenMissing() {
        XCTAssertEqual(OpenAPIController.clampedLimit(nil), OpenAPIController.defaultLimit)
        XCTAssertEqual(OpenAPIController.clampedLimit(nil, default: 42), 42)
    }

    func testClampedLimitEnforcesBounds() {
        XCTAssertEqual(OpenAPIController.clampedLimit(0), 1)
        XCTAssertEqual(OpenAPIController.clampedLimit(-5), 1)
        XCTAssertEqual(OpenAPIController.clampedLimit(1), 1)
        XCTAssertEqual(OpenAPIController.clampedLimit(500), 500)
        XCTAssertEqual(OpenAPIController.clampedLimit(1000), 1000)
        XCTAssertEqual(OpenAPIController.clampedLimit(1001), OpenAPIController.maxLimit)
        XCTAssertEqual(OpenAPIController.clampedLimit(Int.max), OpenAPIController.maxLimit)
    }
}

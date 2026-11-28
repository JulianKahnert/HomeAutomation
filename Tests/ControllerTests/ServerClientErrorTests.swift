//
//  ServerClientErrorTests.swift
//  ControllerTests
//

@testable import ServerClient
import Testing

@Suite("ServerClientError")
struct ServerClientErrorTests {
    @Test("503 from a write route means the change is queued")
    func serviceUnavailableIsBusy() {
        #expect(ServerClientError(undocumentedStatus: 503) == .busy)
    }

    @Test("any other undocumented status stays an unexpected answer")
    func otherStatus() {
        #expect(ServerClientError(undocumentedStatus: 500) == .unexpected(status: 500))
    }

    @Test("the messages are plain sentences, not an OpenAPI dump")
    func messages() {
        #expect(ServerClientError.busy.localizedDescription == "The server is busy. The change is queued and applies in a moment.")
        #expect(ServerClientError.unexpected(status: 500).localizedDescription == "The server answered unexpectedly (status 500).")
    }
}

//
//  AdapterWebSocket.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 26.07.26.
//
//  Server-side WebSocket transport for the StarActorSystem (see docs/adr-001).
//  The adapter connects to `/adapter/v1` (authenticated); frames are pumped
//  into the actor system, which handles hello handshake, calls and replies.

import NIOConcurrencyHelpers
import StarActorSystem
import Vapor

/// `WireConnection` wrapper around Vapor's `WebSocket`. Frames are sent as
/// binary (matching the URLSession client transport, which sends `.data`).
private struct VaporWireConnection: WireConnection {
    let webSocket: WebSocket

    func send(_ data: Data) async throws {
        try await webSocket.send([UInt8](data))
    }

    func close() async {
        try? await webSocket.close(code: .goingAway)
    }
}

/// Registers the adapter WebSocket route on the given (authenticated) route group.
func registerAdapterWebSocket(on routes: some RoutesBuilder, system: StarActorSystem) {
    // Tracks the latest attached socket so a replaced (stale) socket's onClose
    // does not detach the connection that superseded it (latest-connection-wins).
    let currentSocket = NIOLockedValueBox<WebSocket?>(nil)

    routes.webSocket("adapter", "v1", maxFrameSize: WebSocketMaxFrameSize(integerLiteral: 4 << 20)) { _, webSocket async in
        webSocket.pingInterval = .seconds(15)
        currentSocket.withLockedValue { $0 = webSocket }

        // Attach before registering the frame handlers so the client's hello
        // (its first frame) always finds a connection to reply on.
        await system.attach(VaporWireConnection(webSocket: webSocket))

        webSocket.onBinary { _, buffer in
            await system.receive(Data(buffer.readableBytesView))
        }
        webSocket.onText { _, text in
            await system.receive(Data(text.utf8))
        }
        webSocket.onClose.whenComplete { _ in
            let isCurrent = currentSocket.withLockedValue { current in
                guard current === webSocket else { return false }
                current = nil
                return true
            }
            guard isCurrent else { return }
            Task { await system.detach() }
        }
    }
}

//
//  AdapterWebSocket.swift
//  HomeAutomation
//
//  Created by Julian Kahnert on 26.07.26.
//
//  Server-side WebSocket transport for the StarActorSystem (see docs/adr-001).
//  The adapter connects to `/adapter/v1` (authenticated); frames are pumped
//  into the actor system, which handles hello handshake, calls and replies.

import StarActorSystem
import Vapor

/// `WireConnection` wrapper around Vapor's `WebSocket`. Frames are sent as
/// binary (matching the URLSession client transport, which sends `.data`).
private final class VaporWireConnection: WireConnection {
    let webSocket: WebSocket

    init(webSocket: WebSocket) {
        self.webSocket = webSocket
    }

    func send(_ data: Data) async throws {
        try await webSocket.send([UInt8](data))
    }

    func close() async {
        try? await webSocket.close(code: .goingAway)
    }
}

/// Registers the adapter WebSocket route on the given (authenticated) route group.
func registerAdapterWebSocket(on routes: some RoutesBuilder, system: StarActorSystem) {
    routes.webSocket("adapter", "v1", maxFrameSize: WebSocketMaxFrameSize(integerLiteral: 4 << 20)) { _, webSocket async in
        webSocket.pingInterval = .seconds(15)
        let connection = VaporWireConnection(webSocket: webSocket)

        // Register the frame handlers BEFORE attaching so the client's hello
        // (its first frame) can never fall into an unhandled gap. The actor
        // system identity-checks the connection, so stale sockets' frames and
        // closes cannot affect a newer connection.
        webSocket.onBinary { _, buffer in
            await system.receive(Data(buffer.readableBytesView), from: connection)
        }
        webSocket.onText { _, text in
            await system.receive(Data(text.utf8), from: connection)
        }
        webSocket.onClose.whenComplete { _ in
            Task { await system.detach(connection) }
        }

        await system.attach(connection)
    }
}

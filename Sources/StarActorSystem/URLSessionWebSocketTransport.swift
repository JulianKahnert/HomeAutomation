//
//  URLSessionWebSocketTransport.swift
//  HomeAutomationKit
//
//  Created by Julian Kahnert on 26.07.26.
//

#if !os(Linux)
import Foundation
import Logging

/// Client WebSocket transport for the adapter side of the star.
///
/// Runs a single reconnect loop Task: connect → send hello → pump frames into
/// the system; on any error/close: detach + exponential backoff (1 s → 30 s cap,
/// reset after a connection that reached `.up`), retry forever.
public final class URLSessionWebSocketTransport: @unchecked Sendable {
    private let url: URL
    private let bearerToken: String?
    private let system: StarActorSystem
    private let logger = Logger(label: "StarActorSystem.URLSessionWebSocketTransport")

    private let lock = NSLock()
    private var loopTask: Task<Void, Never>?

    public init(url: URL, bearerToken: String?, system: StarActorSystem) {
        self.url = url
        self.bearerToken = bearerToken
        self.system = system
    }

    /// Start the reconnect loop. Idempotent — a running loop is kept.
    public func start() {
        lock.withLock {
            guard loopTask == nil else { return }
            loopTask = Task { [weak self] in
                await self?.runLoop()
            }
        }
    }

    /// Stop the reconnect loop and tear down any live connection.
    public func stop() {
        let task: Task<Void, Never>? = lock.withLock {
            let task = loopTask
            loopTask = nil
            return task
        }
        task?.cancel()
    }

    // MARK: - Reconnect loop

    private func runLoop() async {
        var backoff: Duration = .seconds(1)
        while !Task.isCancelled {
            let reachedUp = await runSingleConnection()
            if Task.isCancelled { break }
            backoff = reachedUp ? .seconds(1) : min(backoff * 2, .seconds(30))
            logger.info("reconnecting in \(backoff)")
            try? await Task.sleep(for: backoff)
        }
        await system.detach()
    }

    /// Runs one connection until it fails or the task is cancelled.
    /// - Returns: whether the connection reached `.up` (used to reset backoff).
    private func runSingleConnection() async -> Bool {
        var request = URLRequest(url: url)
        if let bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        let session = URLSession(configuration: .ephemeral)
        let socketTask = session.webSocketTask(with: request)
        socketTask.maximumMessageSize = 4 << 20
        socketTask.resume()
        logger.info("connecting", metadata: ["url": "\(url)"])

        let connection = URLSessionWireConnection(task: socketTask)
        await system.attach(connection)
        await system.sendHello()

        // Keepalive: a failed ping cancels the socket, which makes receive() throw below.
        let pingTask = Task { [logger] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { return }
                do {
                    try await socketTask.sendPingAsync()
                    logger.debug("ping ok")
                } catch {
                    logger.error("ping failed, tearing down connection: \(error)")
                    socketTask.cancel(with: .goingAway, reason: nil)
                    return
                }
            }
        }

        // Pump inbound frames until the socket fails or we get cancelled.
        do {
            while !Task.isCancelled {
                let message = try await socketTask.receive()
                switch message {
                case .data(let data):
                    await system.receive(data)
                case .string(let string):
                    await system.receive(Data(string.utf8))
                @unknown default:
                    logger.error("unknown WebSocket message type")
                }
            }
        } catch {
            logger.error("connection failed: \(error)")
        }

        pingTask.cancel()
        let reachedUp = system.isConnected
        socketTask.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
        await system.detach()
        return reachedUp
    }
}

// MARK: - WireConnection wrapper

private final class URLSessionWireConnection: WireConnection, @unchecked Sendable {
    private let task: URLSessionWebSocketTask

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func send(_ data: Data) async throws {
        try await task.send(.data(data))
    }

    func close() async {
        task.cancel(with: .goingAway, reason: nil)
    }
}

// MARK: - Helpers

private extension URLSessionWebSocketTask {
    /// async wrapper for the completion-handler based `sendPing`.
    func sendPingAsync() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
#endif

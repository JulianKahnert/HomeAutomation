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

    /// How long a connection may stay attached without completing the hello
    /// handshake before it is torn down and retried (guards against a lost hello).
    static let handshakeTimeout: Duration = .seconds(10)

    private let lock = NSLock()
    private var loopTask: Task<Void, Never>?
    private var socketTask: URLSessionWebSocketTask?

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
        let (task, socket): (Task<Void, Never>?, URLSessionWebSocketTask?) = lock.withLock {
            let task = loopTask
            loopTask = nil
            let socket = socketTask
            socketTask = nil
            return (task, socket)
        }
        task?.cancel()
        // Cancel the live socket directly so a receive() blocked in the loop
        // fails immediately instead of lingering until the next frame/ping.
        socket?.cancel(with: .goingAway, reason: nil)
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
        // Each runSingleConnection() detaches its own connection before
        // returning, so there is nothing left to clean up here.
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
        lock.withLock { self.socketTask = socketTask }
        logger.info("connecting", metadata: ["url": "\(url)"])

        let connection = URLSessionWireConnection(task: socketTask)
        // Subscribe before attach so the `.up` transition cannot be missed.
        let statusStream = system.makeConnectionStatusStream()
        await system.attach(connection)
        await system.sendHello()

        // Handshake watchdog: if the hello reply is lost (e.g. dropped by the
        // server in a registration gap), the connection would sit attached-but-
        // never-up forever. Race the `.up` transition against a timeout; on
        // timeout, cancel the socket so the normal backoff/retry path runs.
        let handshakeTask = Task { [logger] in
            let reachedUp = await withTaskGroup(of: Bool.self) { group in
                group.addTask {
                    for await status in statusStream where status == .up { return true }
                    return false
                }
                group.addTask {
                    try? await Task.sleep(for: Self.handshakeTimeout)
                    return false
                }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
            guard !reachedUp, !Task.isCancelled else { return }
            logger.error("hello handshake not completed within \(Self.handshakeTimeout) — tearing down connection for retry")
            socketTask.cancel(with: .goingAway, reason: nil)
        }

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
                    await system.receive(data, from: connection)
                case .string(let string):
                    await system.receive(Data(string.utf8), from: connection)
                @unknown default:
                    logger.error("unknown WebSocket message type")
                }
            }
        } catch {
            if let httpResponse = socketTask.response as? HTTPURLResponse,
               httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                logger.error("authentication failed — check the server auth token (HTTP \(httpResponse.statusCode))")
            } else if socketTask.closeCode == .policyViolation {
                logger.error("authentication failed — check the server auth token (close code: policyViolation)")
            } else {
                logger.error("connection failed: \(error)")
            }
        }

        handshakeTask.cancel()
        pingTask.cancel()
        let reachedUp = system.isConnected
        socketTask.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
        lock.withLock {
            if self.socketTask === socketTask { self.socketTask = nil }
        }
        await system.detach(connection)
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

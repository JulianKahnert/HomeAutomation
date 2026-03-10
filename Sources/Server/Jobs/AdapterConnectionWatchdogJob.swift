//
//  AdapterConnectionWatchdogJob.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 10.03.26.
//

import Shared

/// Monitors the distributed cluster connection to the FlowKit Adapter and terminates
/// the server process when the connection is irrecoverably lost.
///
/// **Background:** When the FlowKit Adapter restarts (e.g. due to HomeKit errors),
/// the new adapter instance sends `.restInPeace` to the server via the SWIM protocol,
/// marking the server's cluster node as `.down`. After this, the server can no longer
/// communicate with the adapter — all HomeKit commands fail with `nil`. This state is
/// unrecoverable without a server restart.
///
/// This job listens to cluster connection status changes. On `.error`, it waits 60 seconds
/// to allow transient disconnects to recover. If the adapter is still not `.up` after the
/// grace period, it calls `exit(1)` to let Docker restart the container.
struct AdapterConnectionWatchdogJob: Job, Log {
    let actorSystem: CustomActorSystem

    func run() async {
        for await status in await actorSystem.connectionStatus {
            switch status {
            case .up, .joining:
                continue
            case .error:
                break
            }

            log.warning("Adapter connection lost. Waiting 60s for reconnection...")
            try? await Task.sleep(for: .seconds(60))

            let current = await actorSystem.latestConnectionStatus
            if current == .up {
                log.info("Adapter reconnected during grace period.")
                continue
            }

            log.critical("Adapter still disconnected after grace period. Exiting to trigger Docker restart.")
            exit(1)
        }
    }
}

//
//  AdapterConnectionWatchdogJob.swift
//  HomeAutomationServer
//
//  Created by Julian Kahnert on 10.03.26.
//

import Shared

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

//
//  WriteCommand.swift
//  HomeAutomationServer
//

import HAApplicationLayer
import HAModels
import Logging
import Shared

/// What the event loop takes from its stream: an event of the house, or a write of the API. Both take the same
/// way, in the order they arrive, so a write is ordered after every event that was queued before it.
enum HomeInput: Sendable {
    case event(HomeEvent)
    case write(WriteCommand)
}

/// A write of the API layer on its way into the event loop, with the handle the loop answers on.
struct WriteCommand: Sendable {
    enum Kind: Sendable {
        case setState(EntityId, Value)
        case setAutomationActive(name: String, isActive: Bool)
        case stopAutomation(name: String)
        case deploy([any Automatable], location: Location)

        /// For the log line of a command that timed out.
        var name: String {
            switch self {
            case .setState(let entityId, _): return "setState(\(entityId))"
            case .setAutomationActive(let name, let isActive): return "\(isActive ? "activate" : "deactivate")(\(name))"
            case .stopAutomation(let name): return "stop(\(name))"
            case .deploy: return "deploy"
            }
        }
    }

    let kind: Kind
    /// Resolves the caller's wait: the new state for `setState`, `nil` for every other kind. Called once, by the loop.
    let complete: @Sendable (Result<StateChange?, any Error>) -> Void
}

/// The command port over the event flow: every command enters the core as an event in the stream the adapter and the
/// jobs feed, and the caller waits for the loop to answer.
struct EventFlowCommandPort: CommandPort, Log {
    /// How long a caller waits for the loop; the command is handled later all the same.
    static let defaultTimeout: Duration = .seconds(5)

    let sink: HomeEventSink
    var timeout: Duration = Self.defaultTimeout
    /// Of the entities a deploy names: those HomeKit does not know. Asked before the command enters the loop, so a slow
    /// adapter never holds the loop.
    let unknownEntities: @Sendable (Set<EntityId>) async throws -> Set<EntityId>

    func setState(_ entityId: EntityId, value: Value) async throws -> StateChange {
        guard let change = try await send(.setState(entityId, value)) else { throw CoreCommandError.stateUnreadable(entityId) }
        return change
    }

    func setAutomationActive(name: String, to isActive: Bool) async throws {
        _ = try await send(.setAutomationActive(name: name, isActive: isActive))
    }

    func stopAutomation(name: String) async throws {
        _ = try await send(.stopAutomation(name: name))
    }

    func deploy(_ automations: [any Automatable], location: Location, skipValidation: Bool) async throws {
        if skipValidation {
            // Deliberate escape hatch for deploying a config before all devices exist in HomeKit (or while the adapter
            // is offline). It must never be silent: automations referencing unknown entities fail at runtime and flood
            // the critical-log notifier.
            let count = Set(automations.flatMap { $0.getEntityIds() }).count
            log.warning("⚠️ Accepting config with skipValidation=true - \(count) referenced entities were NOT validated against HomeKit")
        } else {
            let missing = try await unknownEntities(Set(automations.flatMap { $0.getEntityIds() }))
            guard missing.isEmpty else { throw CoreCommandError.unknownEntities(missing) }
        }
        _ = try await send(.deploy(automations, location: location))
    }

    private func send(_ kind: WriteCommand.Kind) async throws -> StateChange? {
        let command = kind.name
        let sink = sink
        let timedOut: @Sendable () -> any Error = {
            Self.log.warning("The event loop did not answer in time, the command is handled when it gets there", metadata: ["command": "\(command)"])
            return CoreCommandError.timedOut(command: command)
        }
        let enter: @Sendable () async throws -> StateChange? = {
            try await withCheckedThrowingContinuation { continuation in
                sink.yield(.write(WriteCommand(kind: kind, complete: { continuation.resume(with: $0) })))
            }
        }
        return try await raceTimeout(timeout, timeoutError: timedOut, operation: enter)
    }
}

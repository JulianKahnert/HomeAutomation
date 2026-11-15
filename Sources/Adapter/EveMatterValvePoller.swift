//
//  EveMatterValvePoller.swift
//  Adapter
//

#if canImport(HomeKit) && canImport(Matter)
import Foundation
import HAModels
import HomeKit
import Logging
import Matter
import Synchronization

private let log = Logger(label: "EveMatterValvePoller")

/// Reads the valve position of every Eve Thermo paired over Matter and turns changed values into `valvePosition` items.
///
/// Polls instead of subscribing: the home's Matter controller is an XPC proxy of `homed`, on which only
/// `MTRBaseDevice` reads are proven to work, and a subscription would take one of the few subscription
/// slots of a battery-powered Thread device on HomeKit's fabric for a value that moves slowly.
actor EveMatterValvePoller {
    static let pollInterval: Duration = .seconds(5 * 60)
    /// A Thread device that is asleep or unreachable may never answer; the next accessory must not wait for it.
    static let readTimeout: Duration = .seconds(30)

    private struct MatterNode: Hashable {
        let controllerID: String
        let nodeID: UInt64
    }

    private var changeDetector = ValvePositionChangeDetector()
    /// Whether endpoint 1 of a node has the Thermostat cluster; fixed while the accessory stays paired.
    private var isThermostatByNode: [MatterNode: Bool] = [:]
    /// Nodes whose last read failed, so a lasting failure logs one warning instead of one per poll.
    private var failingNodes: Set<MatterNode> = []

    /// Sends every valve position on the next poll, e.g. after a reconnect to the server.
    func resendOnNextPoll() {
        changeDetector.reset()
    }

    /// Reads all Eve Thermos of `homes` and returns an item for each valve position that changed since it was last returned.
    func poll(homes: [HMHome]) async -> [EntityStorageItem] {
        var items: [EntityStorageItem] = []
        for home in homes {
            let candidates = home.accessories.filter { $0.matterNodeID != nil && $0.heatingService != nil }
            guard !candidates.isEmpty else { continue }

            let controllerID = home.matterControllerID
            let controller = MTRDeviceController.sharedController(withID: controllerID as NSString,
                                                                  xpcConnect: home.matterControllerXPCConnectBlock)
            for accessory in candidates {
                guard let item = await readValvePosition(of: accessory, controllerID: controllerID, controller: controller) else { continue }
                items.append(item)
            }
        }
        return items
    }

    private func readValvePosition(of accessory: HMAccessory, controllerID: String, controller: MTRDeviceController) async -> EntityStorageItem? {
        guard let nodeID = accessory.matterNodeID,
              let placeId = accessory.room?.name else { return nil }
        let node = MatterNode(controllerID: controllerID, nodeID: nodeID)
        let metadata: Logger.Metadata = [
            "room": "\(placeId)",
            "accessory": "\(accessory.name)",
            "matterNodeId": "\(String(nodeID, radix: 16))"
        ]
        let device = MTRBaseDevice(nodeID: NSNumber(value: nodeID), controller: controller)

        do {
            guard try await isThermostat(node: node, device: device, metadata: metadata) else { return nil }

            let rawValue = try await readAttribute(device: device,
                                                   clusterID: EveMatterValve.clusterID,
                                                   attributeID: EveMatterValve.valvePositionAttributeID,
                                                   parse: Self.unsignedInteger)
            if failingNodes.remove(node) != nil {
                log.info("Eve valve position readable again", metadata: metadata)
            }
            guard let percent = EveMatterValve.percent(fromRawValue: rawValue) else {
                log.warning("Eve valve position out of range, skipped", metadata: metadata.merging(["rawValue": "\(rawValue)"]) { _, new in new })
                return nil
            }

            let entityId = EntityId(placeId: placeId,
                                    name: accessory.name,
                                    characteristicsName: accessory.heatingService?.name,
                                    characteristic: .valvePosition)
            let isChange = changeDetector.recordIfChanged(percent, for: entityId)
            log.debug("Read Eve valve position", metadata: metadata.merging([
                "valvePositionPercent": "\(percent)",
                "changed": "\(isChange)"
            ]) { _, new in new })
            guard isChange else { return nil }
            return EntityStorageItem(entityId: entityId, valvePositionPercent: percent)
        } catch {
            let errorMetadata = metadata.merging(["error": "\(error)"]) { _, new in new }
            if failingNodes.insert(node).inserted {
                log.warning("Failed to read Eve valve position over Matter", metadata: errorMetadata)
            } else {
                log.debug("Eve valve position still not readable over Matter", metadata: errorMetadata)
            }
            return nil
        }
    }

    private func isThermostat(node: MatterNode, device: MTRBaseDevice, metadata: Logger.Metadata) async throws -> Bool {
        if let isThermostat = isThermostatByNode[node] {
            return isThermostat
        }
        let clusterIDs = try await readAttribute(device: device,
                                                 clusterID: EveMatterValve.descriptorClusterID,
                                                 attributeID: EveMatterValve.serverListAttributeID,
                                                 parse: Self.unsignedIntegerArray)
        let isThermostat = EveMatterValve.isThermostat(serverClusterIDs: clusterIDs.map { UInt32(truncatingIfNeeded: $0) })
        isThermostatByNode[node] = isThermostat
        log.debug("Classified Matter accessory", metadata: metadata.merging([
            "isThermostat": "\(isThermostat)",
            "serverClusters": "\(clusterIDs.map { "0x" + String($0, radix: 16) }.joined(separator: ","))"
        ]) { _, new in new })
        return isThermostat
    }
}

// MARK: - Matter reads

enum EveMatterReadError: Error, CustomStringConvertible {
    case timeout
    case noValue
    case unexpectedValue(String)

    var description: String {
        switch self {
        case .timeout:
            return "no answer within \(EveMatterValvePoller.readTimeout)"
        case .noValue:
            return "the read returned no attribute value"
        case .unexpectedValue(let value):
            return "unexpected attribute value \(value)"
        }
    }
}

extension EveMatterValvePoller {
    /// Reads one attribute on endpoint 1, failing after `readTimeout` when the device does not answer.
    private func readAttribute<Value: Sendable>(device: MTRBaseDevice,
                                                clusterID: UInt32,
                                                attributeID: UInt32,
                                                parse: @escaping @Sendable (Any?) throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
            let completion = ReadCompletion(continuation)
            completion.startTimeout(after: Self.readTimeout)
            device.readAttributes(withEndpointID: NSNumber(value: EveMatterValve.endpointID),
                                  clusterID: NSNumber(value: clusterID),
                                  attributeID: NSNumber(value: attributeID),
                                  params: nil,
                                  queue: .global(qos: .utility)) { values, error in
                // Parsed here, because the response dictionaries are not Sendable.
                completion.resume(with: Result {
                    if let error { throw error }
                    guard let value = values?.first else { throw EveMatterReadError.noValue }
                    if let attributeError = value[MTRErrorKey] as? NSError { throw attributeError }
                    return try parse(value[MTRDataKey])
                })
            }
        }
    }

    /// An unsigned integer Matter data-value, e.g. `[type: UnsignedInteger, value: 71]`.
    private static func unsignedInteger(_ dataValue: Any?) throws -> UInt64 {
        guard let dictionary = dataValue as? [String: Any],
              dictionary[MTRTypeKey] as? String == MTRUnsignedIntegerValueType,
              let number = dictionary[MTRValueKey] as? NSNumber else {
            throw EveMatterReadError.unexpectedValue(String(describing: dataValue))
        }
        return number.uint64Value
    }

    /// An array of unsigned integers, e.g. the Descriptor cluster's `ServerList`.
    private static func unsignedIntegerArray(_ dataValue: Any?) throws -> [UInt64] {
        guard let dictionary = dataValue as? [String: Any],
              dictionary[MTRTypeKey] as? String == MTRArrayValueType,
              let elements = dictionary[MTRValueKey] as? [[String: Any]] else {
            throw EveMatterReadError.unexpectedValue(String(describing: dataValue))
        }
        return try elements.map { try unsignedInteger($0[MTRDataKey]) }
    }
}

/// Resumes a read's continuation exactly once: with the device's answer or with a timeout, whichever comes first.
private final class ReadCompletion<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, any Error>?
        var timeout: Task<Void, Never>?
    }

    private let state: Mutex<State>

    init(_ continuation: CheckedContinuation<Value, any Error>) {
        state = Mutex(State(continuation: continuation))
    }

    func startTimeout(after duration: Duration) {
        let task = Task { [self] in
            do {
                try await Task.sleep(for: duration)
            } catch {
                return
            }
            resume(with: .failure(EveMatterReadError.timeout))
        }
        let isPending = state.withLock { state in
            state.timeout = task
            return state.continuation != nil
        }
        if !isPending {
            task.cancel()
        }
    }

    func resume(with result: Result<Value, any Error>) {
        let (continuation, timeout) = state.withLock { state in
            let taken = (state.continuation, state.timeout)
            state.continuation = nil
            state.timeout = nil
            return taken
        }
        timeout?.cancel()
        continuation?.resume(with: result)
    }
}

private extension HMAccessory {
    /// The HeaterCooler or Thermostat service, whose name the other heating entities of the accessory carry.
    var heatingService: HMService? {
        services.first { HeatingControlCharacteristic.isHeatingService($0.serviceType) }
    }
}
#endif

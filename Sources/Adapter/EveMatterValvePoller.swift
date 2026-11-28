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
import Shared
import Synchronization

private let log = Logger(label: "EveMatterValvePoller")

/// Reads the valve position and temperature offset of one Eve Thermo paired over Matter on request and turns
/// them into `valvePosition` and `temperatureCalibration` items.
///
/// Reads instead of subscribing: the home's Matter controller is an XPC proxy of `homed`, on which only
/// `MTRBaseDevice` reads are proven to work, and a subscription would take one of the few subscription
/// slots of a battery-powered Thread device on HomeKit's fabric for a value that moves slowly.
/// The server decides when to read, detects changes and keeps the error book; this type only reads.
actor EveMatterValvePoller {
    /// A Thread device that is asleep or unreachable may never answer. All reads of one thermostat together
    /// stay within this limit. It stays below `StarActorSystem`'s remote call timeout (30 s), so a partial
    /// answer (the valve without the offset) still reaches the server in time.
    static let readTimeout: Duration = .seconds(20)

    private struct MatterNode: Hashable {
        let controllerID: String
        let nodeID: UInt64
    }

    /// Whether endpoint 1 of a node has the Thermostat cluster; fixed while the accessory stays paired.
    private var isThermostatByNode: [MatterNode: Bool] = [:]

    /// The Matter accessories of `homes` that have a heating service and are not known to be no thermostat.
    func thermostats(in homes: [HMHome]) -> [Thermostat] {
        var result: [Thermostat] = []
        for home in homes {
            for accessory in home.accessories where accessory.matterNodeID != nil && accessory.heatingService != nil {
                guard let nodeID = accessory.matterNodeID, let placeId = accessory.room?.name else { continue }
                let node = MatterNode(controllerID: home.matterControllerID, nodeID: nodeID)
                guard isThermostatByNode[node] != false else { continue }
                result.append(Thermostat(placeId: placeId, name: accessory.name, characteristicsName: accessory.heatingService?.name))
            }
        }
        return result
    }

    /// Reads one thermostat. Throws when it does not answer in time; returns no item for a Matter accessory
    /// that is no thermostat.
    func read(_ thermostat: Thermostat, homes: [HMHome]) async throws -> [EntityStorageItem] {
        guard let home = homes.first(where: { home in home.accessories.contains { $0.matches(thermostat) } }),
              let accessory = home.accessories.first(where: { $0.matches(thermostat) }),
              let nodeID = accessory.matterNodeID else { throw OptionalError.notFound }
        let controllerID = home.matterControllerID
        let node = MatterNode(controllerID: controllerID, nodeID: nodeID)
        let controller = MTRDeviceController.sharedController(withID: controllerID as NSString,
                                                              xpcConnect: home.matterControllerXPCConnectBlock)
        let device = MTRBaseDevice(nodeID: NSNumber(value: nodeID), controller: controller)
        let deadline = ContinuousClock.now + Self.readTimeout

        if isThermostatByNode[node] == nil {
            let clusterIDs = try await read(device,
                                            EveMatterValve.descriptorClusterID,
                                            EveMatterValve.serverListAttributeID,
                                            deadline: deadline,
                                            parse: Self.unsignedIntegerArray)
            isThermostatByNode[node] = EveMatterValve.isThermostat(serverClusterIDs: clusterIDs.map { UInt32(truncatingIfNeeded: $0) })
        }
        guard isThermostatByNode[node] == true else { return [] }

        let rawValvePosition = try await read(device,
                                              EveMatterValve.clusterID,
                                              EveMatterValve.valvePositionAttributeID,
                                              deadline: deadline,
                                              parse: Self.unsignedInteger)
        // The offset is a bonus: a missing answer must not hide the valve position.
        let rawCalibration: Int64?
        do {
            rawCalibration = try await read(device,
                                            EveMatterValve.thermostatClusterID,
                                            EveMatterValve.localTemperatureCalibrationAttributeID,
                                            deadline: deadline,
                                            parse: Self.signedInteger)
        } catch {
            log.debug("Eve valve offset not read, only the position is reported", metadata: ["thermostat": "\(thermostat)", "error": "\(error)"])
            rawCalibration = nil
        }

        var items: [EntityStorageItem] = []
        if let percent = EveMatterValve.percent(fromRawValue: rawValvePosition) {
            let entityId = EntityId(placeId: thermostat.placeId, name: thermostat.name, characteristicsName: thermostat.characteristicsName, characteristic: .valvePosition)
            if let item = EntityStorageItem(entityId: entityId, value: .number(Double(percent))) { items.append(item) }
        } else {
            log.warning("Eve valve position out of range, skipped", metadata: ["thermostat": "\(thermostat)", "rawValue": "\(rawValvePosition)"])
        }
        if let rawCalibration, let offset = EveMatterValve.calibrationInC(fromRawValue: rawCalibration) {
            let entityId = EntityId(placeId: thermostat.placeId, name: thermostat.name, characteristicsName: thermostat.characteristicsName, characteristic: .temperatureCalibration)
            if let item = EntityStorageItem(entityId: entityId, value: .number(offset)) { items.append(item) }
        }
        return items
    }

    private func read<Value: Sendable>(_ device: MTRBaseDevice,
                                       _ clusterID: UInt32,
                                       _ attributeID: UInt32,
                                       deadline: ContinuousClock.Instant,
                                       parse: @escaping @Sendable (Any?) throws -> Value) async throws -> Value {
        let remaining = ContinuousClock.now.duration(to: deadline)
        guard remaining > .zero else { throw EveMatterReadError.timeout }
        return try await readAttribute(device: device, clusterID: clusterID, attributeID: attributeID, timeout: remaining, parse: parse)
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
                                                timeout: Duration,
                                                parse: @escaping @Sendable (Any?) throws -> Value) async throws -> Value {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
            let completion = ReadCompletion(continuation)
            completion.startTimeout(after: timeout)
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

    /// A signed integer Matter data-value, e.g. `[type: SignedInteger, value: -5]`.
    private static func signedInteger(_ dataValue: Any?) throws -> Int64 {
        guard let dictionary = dataValue as? [String: Any],
              dictionary[MTRTypeKey] as? String == MTRSignedIntegerValueType,
              let number = dictionary[MTRValueKey] as? NSNumber else {
            throw EveMatterReadError.unexpectedValue(String(describing: dataValue))
        }
        return number.int64Value
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
    func matches(_ thermostat: Thermostat) -> Bool {
        matterNodeID != nil && room?.name == thermostat.placeId && name == thermostat.name && heatingService?.name == thermostat.characteristicsName
    }

    /// The HeaterCooler or Thermostat service, whose name the other heating entities of the accessory carry.
    var heatingService: HMService? {
        services.first { HeatingControlCharacteristic.isHeatingService($0.serviceType) }
    }
}
#endif

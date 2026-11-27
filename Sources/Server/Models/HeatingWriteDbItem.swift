//
//  HeatingWriteDbItem.swift
//  HomeAutomationServer
//

import Fluent
import Foundation
import HAModels

final class HeatingWriteDbItem: Model, @unchecked Sendable {
    static let schema = "heatingWrites"

    @ID(key: .id)
    var id: UUID?

    @Field(key: "timestamp")
    var timestamp: Date

    @Field(key: "placeId")
    var placeId: String

    @Field(key: "name")
    var name: String

    @OptionalField(key: "characteristicsName")
    var characteristicsName: String?

    @Field(key: "characteristicType")
    var characteristicType: String

    @Field(key: "reason")
    var reason: String

    @Field(key: "actionName")
    var actionName: String

    @OptionalField(key: "isActive")
    var isActive: Bool?

    @OptionalField(key: "targetTemperatureInC")
    var targetTemperatureInC: Double?

    @OptionalField(key: "planTargetInC")
    var planTargetInC: Double?

    @Field(key: "sentToDevice")
    var sentToDevice: Bool

    init() { }

    init(_ write: HeatingWrite) {
        id = write.id
        timestamp = write.timestamp
        placeId = write.entityId.placeId
        name = write.entityId.name
        characteristicsName = write.entityId.characteristicsName
        characteristicType = write.entityId.characteristicType.rawValue
        reason = write.reason.rawValue
        actionName = write.actionName
        isActive = write.isActive
        targetTemperatureInC = write.targetTemperatureInC
        planTargetInC = write.planTargetInC
        sentToDevice = write.sentToDevice
    }

    func toWrite() throws -> HeatingWrite {
        guard let id,
              let characteristic = CharacteristicsType(rawValue: characteristicType),
              let reason = HeatingWriteReason(rawValue: reason) else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid heating write row \(String(describing: id))"))
        }
        return HeatingWrite(id: id,
                            timestamp: timestamp,
                            entityId: EntityId(placeId: placeId, name: name, characteristicsName: characteristicsName, characteristic: characteristic),
                            reason: reason,
                            actionName: actionName,
                            isActive: isActive,
                            targetTemperatureInC: targetTemperatureInC,
                            planTargetInC: planTargetInC,
                            sentToDevice: sentToDevice)
    }
}

struct HeatingWriteDbRepository: HeatingWriteRepository {
    /// Resolved per query, see `EntityStorageDbRepository.database`.
    let database: @Sendable () -> any Database

    func add(_ write: HeatingWrite) async throws {
        try await HeatingWriteDbItem(write).create(on: database())
    }

    func writes(placeId: String, startDate: Date?, endDate: Date?) async throws -> [HeatingWrite] {
        var query = HeatingWriteDbItem.query(on: database())
            .filter(\.$placeId == placeId)
        if let startDate {
            query = query.filter(\.$timestamp >= startDate)
        }
        if let endDate {
            query = query.filter(\.$timestamp < endDate)
        }
        return try await query
            .sort(\.$timestamp, .ascending)
            .all()
            .map { try $0.toWrite() }
    }

    func lastPlanWrite(placeId: String, before date: Date) async throws -> HeatingWrite? {
        try await HeatingWriteDbItem.query(on: database())
            .filter(\.$placeId == placeId)
            .filter(\.$timestamp < date)
            .filter(\.$planTargetInC != nil)
            .sort(\.$timestamp, .descending)
            .first()
            .map { try $0.toWrite() }
    }

    func lastWrite(placeId: String, radiatorName: String) async throws -> HeatingWrite? {
        try await HeatingWriteDbItem.query(on: database())
            .filter(\.$placeId == placeId)
            .filter(\.$name == radiatorName)
            .filter(\.$sentToDevice == true)
            .sort(\.$timestamp, .descending)
            .first()
            .map { try $0.toWrite() }
    }

    func lastWrites() async throws -> [HeatingWrite] {
        let radiators = try await HeatingWriteDbItem.query(on: database())
            .filter(\.$sentToDevice == true)
            .field(\.$placeId)
            .field(\.$name)
            .unique()
            .all()
        var writes: [HeatingWrite] = []
        for radiator in radiators {
            if let write = try await lastWrite(placeId: radiator.placeId, radiatorName: radiator.name) {
                writes.append(write)
            }
        }
        return writes
    }
}

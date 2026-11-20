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
                            planTargetInC: planTargetInC)
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

    func deleteWrites(olderThan date: Date) async throws {
        try await HeatingWriteDbItem.query(on: database())
            .filter(\.$timestamp < date)
            .delete()
    }
}

//
//  HomeKitInventoryItem.swift
//  HAModels
//

/// One characteristic of everything HomeKit knows, mapped to our model or not. The adapter sends the whole list
/// after each connect and when the homes change; the server keeps it in the `homekitInventory` table so questions
/// like "which contact sensor is missing from the automations" can be answered with a query.
public struct HomeKitInventoryItem: Sendable, Codable, Hashable {
    public var homeName: String
    public var roomName: String
    public var accessoryName: String
    public var manufacturer: String?
    public var model: String?
    /// The HomeKit service type (a UUID string).
    public var serviceType: String
    public var serviceName: String
    /// The HomeKit characteristic type (a UUID string).
    public var characteristicType: String
    public var characteristicDescription: String
    /// Our type for this characteristic; `nil` when the adapter maps it to none (unmapped or skipped).
    public var mappedType: CharacteristicsType?
    public var isReadable: Bool
    public var isNotifiable: Bool
    public var isWritable: Bool
    /// The current value as text; `nil` for a write-only characteristic or a failed read.
    public var value: String?

    public init(
        homeName: String,
        roomName: String,
        accessoryName: String,
        manufacturer: String? = nil,
        model: String? = nil,
        serviceType: String,
        serviceName: String,
        characteristicType: String,
        characteristicDescription: String,
        mappedType: CharacteristicsType? = nil,
        isReadable: Bool,
        isNotifiable: Bool,
        isWritable: Bool,
        value: String? = nil
    ) {
        self.homeName = homeName
        self.roomName = roomName
        self.accessoryName = accessoryName
        self.manufacturer = manufacturer
        self.model = model
        self.serviceType = serviceType
        self.serviceName = serviceName
        self.characteristicType = characteristicType
        self.characteristicDescription = characteristicDescription
        self.mappedType = mappedType
        self.isReadable = isReadable
        self.isNotifiable = isNotifiable
        self.isWritable = isWritable
        self.value = value
    }
}

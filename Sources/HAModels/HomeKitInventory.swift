//
//  HomeKitInventory.swift
//  HAModels
//

/// Everything HomeKit knows, built from HomeKit's own model and not from our mapping: homes, their rooms, the
/// accessories of a room, their services and characteristics. The server pulls it from the adapter and keeps it
/// in the `homekitInventory` table, so questions like "which contact sensor is missing from the automations"
/// can be answered with a query.
public struct HomeKitInventory: Sendable, Codable, Hashable {
    public var homes: [Home]

    public init(homes: [Home]) {
        self.homes = homes
    }

    public struct Home: Sendable, Codable, Hashable {
        public var name: String
        public var rooms: [Room]

        public init(name: String, rooms: [Room]) {
            self.name = name
            self.rooms = rooms
        }
    }

    public struct Room: Sendable, Codable, Hashable {
        public var name: String
        public var accessories: [Accessory]

        public init(name: String, accessories: [Accessory]) {
            self.name = name
            self.accessories = accessories
        }
    }

    public struct Accessory: Sendable, Codable, Hashable {
        public var name: String
        public var manufacturer: String?
        public var model: String?
        /// HomeKit's localized category name, e.g. "Sensor".
        public var category: String
        public var isReachable: Bool
        public var services: [Service]

        public init(name: String, manufacturer: String? = nil, model: String? = nil, category: String, isReachable: Bool, services: [Service]) {
            self.name = name
            self.manufacturer = manufacturer
            self.model = model
            self.category = category
            self.isReachable = isReachable
            self.services = services
        }
    }

    public struct Service: Sendable, Codable, Hashable {
        /// The HomeKit service type (a UUID string).
        public var type: String
        /// HomeKit's localized description of the type, e.g. "Contact Sensor".
        public var typeDescription: String
        public var name: String
        public var isPrimary: Bool
        public var characteristics: [Characteristic]

        public init(type: String, typeDescription: String, name: String, isPrimary: Bool, characteristics: [Characteristic]) {
            self.type = type
            self.typeDescription = typeDescription
            self.name = name
            self.isPrimary = isPrimary
            self.characteristics = characteristics
        }
    }

    public struct Characteristic: Sendable, Codable, Hashable {
        /// The HomeKit characteristic type (a UUID string).
        public var type: String
        public var typeDescription: String
        public var isReadable: Bool
        public var isNotifiable: Bool
        public var isWritable: Bool
        /// Our type for this characteristic; `nil` when the adapter maps it to none (unmapped or skipped).
        public var mappedType: CharacteristicsType?
        /// The current value as text; `nil` for a write-only characteristic, a failed read or a read that took too long.
        public var value: String?

        public init(
            type: String,
            typeDescription: String,
            isReadable: Bool,
            isNotifiable: Bool,
            isWritable: Bool,
            mappedType: CharacteristicsType? = nil,
            value: String? = nil
        ) {
            self.type = type
            self.typeDescription = typeDescription
            self.isReadable = isReadable
            self.isNotifiable = isNotifiable
            self.isWritable = isWritable
            self.mappedType = mappedType
            self.value = value
        }
    }
}

public extension HomeKitInventory {
    /// One row per characteristic, with the names of its home, room, accessory and service.
    var rows: [Row] {
        homes.flatMap { home in
            home.rooms.flatMap { room in
                room.accessories.flatMap { accessory in
                    accessory.services.flatMap { service in
                        service.characteristics.map { Row(home: home, room: room, accessory: accessory, service: service, characteristic: $0) }
                    }
                }
            }
        }
    }

    struct Row: Sendable, Hashable {
        public let homeName: String
        public let roomName: String
        public let accessory: Accessory
        public let service: Service
        public let characteristic: Characteristic

        init(home: Home, room: Room, accessory: Accessory, service: Service, characteristic: Characteristic) {
            homeName = home.name
            roomName = room.name
            var bare = accessory
            bare.services = []
            self.accessory = bare
            var bareService = service
            bareService.characteristics = []
            self.service = bareService
            self.characteristic = characteristic
        }
    }
}

public extension HomeKitInventory {
    /// How much HomeKit has, for one log line.
    struct Summary: Sendable, Equatable, CustomStringConvertible {
        public let homes: Int
        public let rooms: Int
        public let accessories: Int
        public let services: Int
        public let characteristics: Int
        public let unmappedCharacteristics: Int
        public let unreachableAccessories: Int

        public var description: String {
            "homes=\(homes) rooms=\(rooms) accessories=\(accessories) services=\(services) characteristics=\(characteristics) "
                + "unmapped=\(unmappedCharacteristics) unreachable=\(unreachableAccessories)"
        }
    }

    var summary: Summary {
        let rooms = homes.flatMap(\.rooms)
        let accessories = rooms.flatMap(\.accessories)
        let services = accessories.flatMap(\.services)
        let characteristics = services.flatMap(\.characteristics)
        return Summary(homes: homes.count,
                       rooms: rooms.count,
                       accessories: accessories.count,
                       services: services.count,
                       characteristics: characteristics.count,
                       unmappedCharacteristics: characteristics.filter { $0.mappedType == nil }.count,
                       unreachableAccessories: accessories.filter { !$0.isReachable }.count)
    }

    /// One line per accessory: room, name, manufacturer and model, service types.
    var accessoryLines: [String] {
        homes.flatMap { home in
            home.rooms.flatMap { room in
                room.accessories.map { accessory in
                    let maker = [accessory.manufacturer, accessory.model].compactMap(\.self).joined(separator: " ")
                    let services = accessory.services.map(\.typeDescription).joined(separator: ", ")
                    return "[\(home.name)] \(room.name) / \(accessory.name) (\(maker))\(accessory.isReachable ? "" : " UNREACHABLE"): \(services)"
                }
            }
        }
    }
}

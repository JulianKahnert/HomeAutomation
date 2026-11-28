//
//  FireplaceContentState.swift
//  HAModels
//

import Foundation

/// The Live Activity data format of the fireplace question "Ist der Kamin noch an?" (glossary: fireplace question).
///
/// The server starts it on every device when it asks and ends it on every device once one resident answered,
/// the fireplace went off another way, or nobody answered within `Fireplace.answerTimeout`.
public struct FireplaceContentState: Hashable, Sendable {
    /// The name used in the APNS `attributes-type` field for push-to-start Live Activities.
    ///
    /// IMPORTANT: This value MUST exactly match the name of the `ActivityAttributes` struct used in the iOS app
    /// (`Sources/Controller/LiveActivity/FireplaceAttributes.swift`), or APNS drops the start silently.
    public static let activityTypeName = "FireplaceAttributes"

    /// When the fireplace was switched on.
    public let since: Date
    /// When the server switches the fireplace off if nobody answers.
    public let endsAt: Date

    public init(since: Date, endsAt: Date) {
        self.since = since
        self.endsAt = endsAt
    }

    /// The content of the end update: ActivityKit decodes it, the Live Activity is gone right after.
    public static let ended = FireplaceContentState(since: Date(timeIntervalSince1970: 0), endsAt: Date(timeIntervalSince1970: 0))
}

extension FireplaceContentState: Codable {
    private enum CodingKeys: String, CodingKey {
        case since, endsAt
    }

    // Dates travel as ISO 8601 strings, so the APNS payload decodes the same in ActivityKit whatever date
    // strategy the server's encoder uses (like `WindowContentState`).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        since = try Self.decodeDate(forKey: .since, in: container)
        endsAt = try Self.decodeDate(forKey: .endsAt, in: container)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(since.ISO8601Format(), forKey: .since)
        try container.encode(endsAt.ISO8601Format(), forKey: .endsAt)
    }

    private static func decodeDate(forKey key: CodingKeys, in container: KeyedDecodingContainer<CodingKeys>) throws -> Date {
        let string = try container.decode(String.self, forKey: key)
        do {
            return try Date(string, strategy: .iso8601)
        } catch {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Invalid ISO 8601 date: \(string)")
        }
    }
}

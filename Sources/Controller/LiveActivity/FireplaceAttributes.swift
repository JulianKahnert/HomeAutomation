//
//  FireplaceAttributes.swift
//  ControllerFeatures
//

#if os(iOS)
import ActivityKit
import Foundation
import HAModels

/// The Live Activity of the fireplace question "Ist der Kamin noch an?". The server starts it by push on every
/// device; its name is `FireplaceContentState.activityTypeName`.
public struct FireplaceAttributes: ActivityAttributes {
    public typealias ContentState = FireplaceContentState

    public init() {}
}
#endif

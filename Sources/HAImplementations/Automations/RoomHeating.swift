//
//  RoomHeating.swift
//  HAImplementations
//

import Foundation
import HAModels

/// Heats one room (glossary: room) after its plan. It is the only writer of the room's radiators.
///
/// It writes the plan target at each switch point and once after a configuration deploy. A plain server
/// start writes nothing, so a manual change at a radiator stays until the next switch point.
public struct RoomHeating: Automatable {
    public var isActive = true
    public let name: String
    public let placeId: PlaceId
    public let radiators: [Radiator]
    /// `nil` for a room without a plan of its own: it follows the standard plan.
    public let plan: HeatingPlan?
    public let configuration: HeatingConfiguration

    public var triggerEntityIds: Set<EntityId> { [] }

    /// The plan this room follows.
    public var effectivePlan: HeatingPlan { plan ?? configuration.standardPlan }

    public init(_ name: String, placeId: PlaceId, radiators: [Radiator], plan: HeatingPlan? = nil, configuration: HeatingConfiguration) {
        self.name = name
        self.placeId = placeId
        self.radiators = radiators
        self.plan = plan
        self.configuration = configuration
    }

    public func shouldTrigger(with event: HomeEvent, using hm: HomeManagable) async throws -> Bool {
        switch event {
        case .time(let date):
            return effectivePlan.switchPoint(at: date) != nil
        case .configDeployed:
            return true
        case .serverStarted, .change, .sunrise, .sunset:
            return false
        }
    }

    public func execute(using hm: HomeManagable) async throws {
        try await execute(using: hm, now: Date())
    }

    /// Writes the plan target of `now` to every radiator. Recomputes everything from `now`, so a
    /// trigger that supersedes a running run needs nothing from it.
    ///
    /// The reason is `plan` in the minute of a switch point and `system` otherwise, i.e. after a deploy;
    /// both carry the plan target.
    func execute(using hm: HomeManagable, now: Date) async throws {
        let plan = effectivePlan
        guard let target = plan.planTarget(at: now) else {
            log.warning("Room \(placeId) has no plan target at \(now)")
            return
        }
        let reason: HeatingWriteReason = plan.switchPoint(at: now) != nil ? .plan : .system

        await HeatingWriteContext.withReason(reason, planTargetInC: target) {
            for radiator in radiators {
                await radiator.setTarget(target, with: hm)
            }
        }
    }
}
